# Odysseus implementation roadmap

**Audit date:** 2026-10-31 · **Revision:** `6ee21d6`
**Ordering principle:** *make the pipeline correct and testable before making it feature-rich.* Every phase below must leave the app shippable. No task in Phase 2+ may be started while a Phase 0 defect is open.

Complexity: **S** ≤ 1 day · **M** 1–3 days · **L** 1–2 weeks · **XL** > 2 weeks (all estimates assume one experienced iOS engineer).

---

## Phase 0 — Stop the bleeding (target: 1 week)

The app currently leaks a certificate password through a URL, can dead-end the primary download path, and can crash on three bad-input paths. None of these require new features; all are prerequisites for testing anything else.

### ODY-001 — Percent-encode and gate certificate export
- **Priority** P0 · **Complexity** S · **Depends on** —
- **Files:** modify `Feather/Utilities/FR.swift` (`exportCertificateAndOpenUrl`), `Feather/FeatherApp.swift` (`_handleURL`), `Feather/Views/Settings/SettingsView.swift` (call site)
- **Upstream:** none — the defect exists in the Feather lineage; do not "sync" it back
- **Behaviour:** URL built with `URLComponents`/`percentEncodedQueryItems`; Face ID (or passcode) required before export, matching `ODAppleIDView.swift:310–316`; if the encoded URL exceeds 8 KB, present the share sheet with the `.p12` instead of a URL; the import handler accepts the same encoding it produces
- **Acceptance:** hostile-password table round-trips; exporting never places an unencoded password in a URL; cancel at the biometric prompt aborts the export
- **Tests:** `CertificateExportURLTests` (new), D-12
- **Licence:** n/a

### ODY-002 — Make download/import failure terminal and specific
- **Priority** P0 · **Complexity** M · **Depends on** —
- **Files:** modify `Feather/Backend/Observable/DownloadManager.swift` (`didFinishDownloadingTo`, `didCompleteWithError`), `Feather/Backend/Odysseus/ODSignPipeline.swift` (`downloadEnded`, `_didImport`), `Feather/Utilities/FR.swift` (error surface)
- **Behaviour:** import failure removes the row, cleans the temp file and publishes `ODSignError.importFailed(reason:)`; the 3-second timer is replaced by an explicit terminal event; a late import still signs (BUG-004); network failures keep their `Error` and offer retry
- **Acceptance:** after a forced import error the library row is gone, a message names the cause, and the app can re-download; a 5-second import still reaches `.signing`
- **Tests:** BUG-002/003/004 tests, D-08
- **Licence:** n/a

### ODY-003 — Remove the crash sites and the private API
- **Priority** P0 · **Complexity** S · **Depends on** —
- **Files:** modify `Feather/Utilities/ARDecompression/AR.swift:14`, `Feather/Backend/Server/ServerInstaller+TLS.swift:19–20`, `Feather/Backend/Certificates/ODX509.swift:172`, `Feather/Utilities/MobileGestalt.swift` (replace the `dlopen`/`MGCopyAnswer` private API with `sysctlbyname("hw.machine")`)
- **Behaviour:** each crash site becomes a typed `throw` with a user-facing message; the device-model lookup uses public API only; no change to success paths
- **Acceptance:** malformed `.deb`, missing network interface and half-imported certificate all produce errors, not terminations
- **Tests:** BUG-008/009/010 tests, plus a grep assertion that `dlopen`/`MGCopyAnswer` never reappear
- **Licence:** n/a

### ODY-004 — CI invariant gate
- **Priority** P0 · **Complexity** S · **Depends on** —
- **Files:** create `scripts/ci/invariants.sh`; modify `.github/workflows/build.yml`
- **Behaviour:** fails the build on new `try!`/`as!`/`print(`, on a missing `Package.resolved`, on unresolved `license_plist.yml` paths, and on a missing required Info.plist key
- **Acceptance:** a deliberate violation fails CI with a readable message
- **Tests:** the script itself
- **Licence:** n/a

### ODY-005 — Local-network declaration and loopback binding
- **Priority** P0 · **Complexity** S · **Depends on** —
- **Files:** modify `Feather/Resources/Info.plist`, `Feather/Backend/Server/ServerInstaller+TLS.swift:36`, `ServerInstaller.swift`
- **Behaviour:** add `NSLocalNetworkUsageDescription`; bind `127.0.0.1` unless the selected transport genuinely needs LAN access; handle permission denial with an explanatory error
- **Acceptance:** D-09 shows an explanation, not a hang; plist invariant test passes
- **Tests:** `PlistInvariantTests`, D-09
- **Licence:** n/a

### ODY-006 — Pin dependencies and publish notices
- **Priority** P0 · **Complexity** S · **Depends on** —
- **Files:** create `THIRD_PARTY_NOTICES.md`; modify `SideSign/Package.swift` (branch → revision), commit `Package.resolved` (root and `SideSign/`), fix `license_plist.yml` paths
- **Upstream:** none — operational
- **Behaviour:** reproducible resolution; AGPL components enumerated with revisions
- **Acceptance:** two clean builds resolve identical revisions; notices list every AGPL/Apache/BSD component
- **Tests:** `DependencyPinTests`, `LicenseManifestTests`
- **Licence:** closes L-01/L-02/L-03

---

## Phase 1 — A testable, secure pipeline (target: 2–3 weeks)

### ODY-101 — Introduce the four service seams
- **Priority** P1 · **Complexity** L · **Depends on** ODY-001…006
- **Files:** create `Feather/Backend/Services/{SigningService,InstallService,DownloadService,SourceService}.swift` (protocols) and `Live*` adapters wrapping `FR`, `ServerInstaller`, `DownloadManager`, `SourcesViewModel`; modify `ODSignPipeline.swift` to compose them; modify `FeatherApp.swift` for injection
- **Upstream:** none (structural)
- **Behaviour:** no user-visible change; identical call ordering
- **Acceptance:** existing 16 tests still pass; the pipeline is constructible in tests with fakes; no file under `Views/` calls `FR.` or `ServerInstaller.` directly
- **Tests:** fake-driven pipeline suites
- **Licence:** n/a

### ODY-102 — Certificate store: keychain password, file protection, backup exclusion
- **Priority** P0 · **Complexity** M · **Depends on** ODY-101
- **Files:** modify `Feather/Backend/Storage/Storage+Certificate.swift`, `Feather/Utilities/Handlers/CertificateFileHandler.swift`, `Feather/Backend/AppleID/ODKeychain.swift`; create `Feather/Backend/Certificates/ODCertificateStore.swift`
- **Behaviour:** `.p12` password migrates from the Core Data attribute to the keychain (one-time migration on launch, old value nulled); certificate directory gets `completeUntilFirstUserAuthentication` protection and `isExcludedFromBackup`; delete uses quarantine semantics
- **Acceptance:** after migration the Core Data attribute is empty for every record; `NSFileProtection` attribute is set on the directory; delete failure keeps the record and informs the user
- **Tests:** migration, BUG-006, `KeychainAccessibilityTests`
- **Licence:** n/a

### ODY-103 — Explicit pipeline state machine
- **Priority** P1 · **Complexity** M · **Depends on** ODY-101
- **Files:** create `Feather/Backend/Odysseus/ODSignState.swift`; modify `ODSignPipeline.swift`
- **Behaviour:** phases become an enum with legal transitions; every terminal state is reachable exactly once; cancellation is a state, not an absence
- **Acceptance:** property-style test over all event sequences yields no invalid transition and no stuck `.downloading`
- **Tests:** state-machine suite
- **Licence:** n/a

### ODY-104 — Archive validation before extraction
- **Priority** P1 · **Complexity** M · **Depends on** ODY-101
- **Files:** modify `Feather/Utilities/Handlers/AppFileHandler.swift` (`extract()`); create `Feather/Utilities/Archive/ODArchivePolicy.swift`
- **Behaviour:** reject entries with absolute or `..` paths, > 20 000 entries, or expanded size > 4 GB / ratio > 200:1; report a specific error
- **Acceptance:** `zipbomb.ipa` and `traversal.zip` are rejected without writing outside the sandbox; real fixtures still import
- **Tests:** archive-limit suite, S-05
- **Licence:** n/a

---

## Phase 2 — Signing correctness and install reliability (target: 3–4 weeks)

### ODY-201 — Verify what was signed
- **Priority** P1 · **Complexity** L · **Depends on** ODY-101
- **Files:** create `Feather/Backend/Signing/ODSignatureVerifier.swift`; modify `Feather/Utilities/Handlers/ZsignHandler.swift`
- **Behaviour:** replace the `checkSigned` presence check with verification of the code-directory hash, entitlements presence, bundle-id match against the profile, and that every nested Mach-O is signed
- **Acceptance:** a fixture signed with a mismatched bundle id is rejected; a valid fixture passes; failure names the failing component
- **Tests:** integration suite over `frameworks-app.ipa`
- **Licence:** n/a (own code; no third-party copy)

### ODY-202 — Entitlements inspection and compatibility check
- **Priority** P2 · **Complexity** L · **Depends on** ODY-201
- **Files:** create `Feather/Backend/Signing/ODEntitlementsReader.swift` + `ODEntitlementPolicy.swift`; modify `Feather/Views/Signing/Shared/SigningEntitlementsView.swift`
- **Upstream:** adapt `RyukSign/Utilities/MachOEntitlements.swift` + `Backend/Observable/EntitlementsManager.swift` (GPL-3.0)
- **Behaviour:** show current entitlements, flag ones the profile cannot grant, allow a file override (existing option)
- **Acceptance:** an app requesting `com.apple.developer.healthkit` with a free profile is flagged before signing; ported code carries a provenance header
- **Tests:** entitlement-policy table tests
- **Licence:** GPL-3.0 — notice + provenance comment

### ODY-203 — Install transport diagnostics and retry
- **Priority** P1 · **Complexity** M · **Depends on** ODY-101
- **Files:** modify `Feather/Backend/Server/ServerInstaller.swift`, `Feather/Backend/Observable/InstallerStatusViewModel.swift`, `Feather/Views/Odysseus/Install/ODInstallSheet.swift`
- **Behaviour:** each transport reports a typed failure (server not started, manifest rejected, device refused, permission denied) and offers one retry without re-signing
- **Acceptance:** D-01…D-03 and D-09 each produce a distinct message
- **Tests:** D-01…D-03, D-09
- **Licence:** n/a

---

## Phase 3 — Source reliability and update visibility (target: 2–3 weeks)

### ODY-301 — Source service with offline cache and health
- **Priority** P1 · **Complexity** L · **Depends on** ODY-101
- **Files:** create `Feather/Backend/Sources/{ODSourceCache,ODSourceHealth}.swift`; move `Views/Sources/SourcesViewModel.swift` → `Backend/Sources/ODSourceService.swift`; modify `ODCatalogStore.swift`
- **Behaviour:** last-good repository JSON persisted per source; per-source state (`ok`, `stale`, `failed(reason)`); refresh coalesces instead of dropping (BUG-011); duplicate detection normalises URL + identifier
- **Acceptance:** launching in airplane mode shows the storefront from cache with a "last updated" label; a 500-returning source shows a red state and a retry; two adds of the same source create one record
- **Tests:** source-service suite, A07/A08/A09/A11
- **Licence:** n/a

### ODY-302 — Update checking for signed apps
- **Priority** P1 · **Complexity** L · **Depends on** ODY-301, ODY-102
- **Files:** create `Feather/Backend/Updates/ODUpdateChecker.swift`, `ODVersionComparator.swift`; add attribute `sourceTrackID` to `Signed`; modify `ODLibraryView.swift`, `ODSignPipeline.swift` (updates must reuse the stored options)
- **Upstream:** adapt `RyukSign/Backend/Observable/AppUpdateChecker.swift` (GPL-3.0) — take the version comparison and the source lookup; **do not** take its background `fetchRequest` usage or its name-based matching
- **Behaviour:** match on stored bundle id first, then on the signing-time identifier override; compare versions with a shared comparator; show an update pill; "Update" re-signs with the previous options
- **Acceptance:** an app installed at 1.0 with 1.1 available shows the pill; PPQ-protected apps do not produce false positives; update preserves options
- **Tests:** comparator table (`1.0 < 1.0.1 < 1.1 < 1.10`), matching rules, D-14
- **Licence:** GPL-3.0 — notice + provenance

### ODY-303 — Storefront polish: priority, categories, duplicate choice
- **Priority** P3 · **Complexity** M · **Depends on** ODY-301
- **Files:** modify `ODCatalog.swift`, `ODCatalogStore.swift`, `ODDiscoverView.swift`; add `ODSourcePriority` in `ODPrefs`
- **Behaviour:** user-ordered source priority resolves duplicate bundle ids; "other sources" sheet on the app page; per-source filter
- **Acceptance:** reordering sources changes the featured entry deterministically
- **Tests:** catalog determinism tests
- **Licence:** n/a

---

## Phase 4 — Feature depth (target: 4–6 weeks)

### ODY-401 — Entitlements and Info.plist editors
- **Priority** P2 · **Complexity** XL · **Depends on** ODY-202
- **Files:** create `Feather/Views/Signing/ODEntitlementsEditorView.swift`, `ODPlistEditorView.swift`, `Feather/Backend/Signing/ODPlistPlan.swift`, `ODPlistDiff.swift`
- **Upstream:** adapt RyukSign `InfoPlistPlan.swift`, `PlistDiff.swift` (GPL-3.0)
- **Behaviour:** view/add/remove entitlements; diff-based plist edits with a dry-run preview
- **Acceptance:** editing an entitlement changes the signed binary; a diff preview matches the result byte-for-byte
- **Tests:** plan/diff unit tests, integration sign
- **Licence:** GPL-3.0

### ODY-402 — Bulk signing queue
- **Priority** P3 · **Complexity** L · **Depends on** ODY-101, ODY-103
- **Files:** create `Feather/Backend/Queue/ODSignQueue.swift`, `Feather/Views/Odysseus/Library/ODBatchSignView.swift`
- **Upstream:** adapt `RyukSign/Backend/Observable/BatchJobRunner.swift` concept (GPL-3.0); no premium gating
- **Behaviour:** select N apps → one identity + options → serial sign → per-item status → install all
- **Acceptance:** 10 apps sign serially with cancellation between items and no memory growth above 200 MB
- **Tests:** queue unit tests with fakes, D-15 (batch)
- **Licence:** GPL-3.0

### ODY-403 — Backup and restore
- **Priority** P3 · **Complexity** L · **Depends on** ODY-102
- **Files:** create `Feather/Backend/Backup/ODBackup.swift` (archive format + optional passphrase)
- **Upstream:** choose **one** — RyukSign `BackupManager`/`BackupCrypto` or SideStore `SideBackup`; do not mix AGPL with the current design
- **Behaviour:** export certificates (encrypted), signed apps, sources and prefs into one archive; restore with conflict handling
- **Acceptance:** round-trip on a device with 3 certificates and 5 apps; wrong passphrase fails cleanly
- **Tests:** format tests + D-16
- **Licence:** record the chosen source

### ODY-404 — Signing diagnostics record
- **Priority** P3 · **Complexity** S · **Depends on** ODY-101
- **Files:** create `Feather/Backend/Diagnostics/ODSignRun.swift`; modify `ODDiagnosticsView.swift`
- **Upstream:** adapt `RyukSign/Utilities/SigningLog.swift` (GPL-3.0)
- **Behaviour:** one structured record per signing (inputs, certificate id, policy decisions, timings, outcome), exportable with the log bundle
- **Acceptance:** a failed signing produces a record that names the stage and reason without secrets
- **Tests:** redaction test (no password, no p12 bytes)
- **Licence:** GPL-3.0

---

## Phase 5 — To a stable release (target: 3–4 weeks)

### ODY-501 — Executed device matrix
- **Priority** P1 · **Complexity** M · **Depends on** Phase 2
- **Files:** create `Documentation/Audit/device-runs/` template + `.github/ISSUE_TEMPLATE/release.md`
- **Behaviour:** D-01…D-14 executed on two device generations for the release build; results committed
- **Acceptance:** every row has a recorded pass, or an accepted, written exception
- **Tests:** the matrix itself
- **Licence:** n/a

### ODY-502 — Accessibility pass
- **Priority** P4 · **Complexity** M · **Depends on** —
- **Files:** modify `Views/Odysseus/**` (labels, traits), add `AccessibilityTests` for critical flows
- **Acceptance:** VoiceOver reaches every action in Library, Signing and Sources; Dynamic Type XL does not clip primary actions
- **Tests:** D-15
- **Licence:** n/a

### ODY-503 — Localisation groundwork
- **Priority** P4 · **Complexity** M · **Depends on** —
- **Files:** reconcile `Feather/Resources/Localizable.xcstrings` (276 keys) with the 741 `.localized(` call sites; add one pilot locale
- **Acceptance:** String Catalog covers every user-facing string; pilot locale renders without truncation on the primary screens
- **Licence:** n/a

### ODY-504 — Library scale
- **Priority** P3 · **Complexity** M · **Depends on** ODY-302
- **Files:** modify `ODLibraryView.swift`, `Storage+Shared.swift` (paged fetch, index on `bundleIdentifier`)
- **Acceptance:** cold start with 500 records under 1.5 s; scrolling at 60 fps
- **Tests:** D-13
- **Licence:** n/a

---

## Dependency graph (critical path)

```
ODY-001 ─┐
ODY-002 ─┼─► ODY-006 ─► ODY-101 ─► ODY-102 ─► ODY-302 ─► ODY-402
ODY-003 ─┤                │           │
ODY-004 ─┤                ├─► ODY-103 ─┘
ODY-005 ─┘                ├─► ODY-104
                          ├─► ODY-201 ─► ODY-202 ─► ODY-401
                          ├─► ODY-203
                          └─► ODY-301 ─► ODY-303
```

The two long poles are **ODY-101 (seams)** and **ODY-301 (source service)**. Everything user-visible in Phases 3–4 queues behind them, which is precisely why bulk signing and editors are *not* early: they would be built on untestable foundations and would have to be re-done.

---

## Effort summary

| Phase | Tasks | Estimate | Exit criterion |
|---|---|---|---|
| 0 | 6 | ~1 week | no credential leak in a URL; no dead-end download; CI invariants live |
| 1 | 4 | 2–3 weeks | pipeline testable; secrets at rest protected |
| 2 | 3 | 3–4 weeks | signed output is verified; install failures are explainable |
| 3 | 3 | 2–3 weeks | storefront works offline; updates visible |
| 4 | 4 | 4–6 weeks | editor, batch, backup, diagnostics |
| 5 | 4 | 3–4 weeks | device matrix executed; release gate satisfied |

**Fastest path to a stable release:** Phase 0 → Phase 1 → ODY-201/203 → ODY-301 → ODY-501, i.e. **skip all of Phase 4**. That sequence yields a product that signs and installs verifiably, explains its failures, works offline, and has been proven on hardware — which is what "stable" means here; the editors and batch signing are multiplicative on a pipeline that is not yet proven.

---

## Explicit non-goals (unchanged from the audit scope)

- LiveContainer-class execution (G01–G08): **not on this roadmap**. See `ODYSSEUS_ARCHITECTURE_AUDIT.md` §8.
- Merging LiveContainer, SideStore or FlekDeck into the signing app: not on this roadmap.
- FlareStore/Zeus feature parity claims: none may be made; they have no public source.
