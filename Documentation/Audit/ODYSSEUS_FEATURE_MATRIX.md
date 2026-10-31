# Odysseus feature matrix

**Audit date:** 2026-10-31 · **Revision audited:** `6ee21d6` · **Rows:** 118

Every row is traced to source code. A row is only `COMPLETE` when the full path (UI → back end → filesystem/network/engine) exists and is reachable; the `Evidence` column says whether that path has actually been exercised. Upstream references are file paths at the commits pinned in `UPSTREAM_SOURCE_REGISTER.md`.

## Status definitions

| Status | Meaning |
|---|---|
| **COMPLETE** | End-to-end implementation present and reachable. Build-verified by CI. Device behaviour may still be unverified — see `Evidence`. |
| **PARTIAL** | Implementation exists but a required part of the capability is missing or degraded. The gap is named. |
| **BROKEN** | Reachable but has a confirmed defect. Cross-referenced to `ODY-BUG-*` or `S-*`. |
| **MISSING** | No implementation found. |
| **UNSUPPORTED** | Not achievable with the current architecture, entitlements, or stock-iOS constraints. |
| **NEEDS_INVESTIGATION** | Behaviour depends on code outside this repository or on a library whose handling was not provable statically. |

## Evidence definitions

`BUILD` = compiled and packaged by a green CI run · `UNIT` = covered by an XCTest case · `DEVICE` = exercised on hardware (**none exists anywhere in the project**) · `NONE` = static inspection only.

---

## A. App discovery and source management

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| A01 | AltStore / AltStore-PAL source JSON parsing | COMPLETE | `AltSourceKit/Sources/AltSourceKit/Models/ASRepository.swift` | AltStore `Shared/`; Feather `AltSourceKit/` | reuse (already vendored) | P2 | BUILD |
| A02 | ESign-style source support (decrypt/deobfuscate) | COMPLETE | `AltSourceKit/.../ASDecrypt.swift`, `ASDeobfuscator.swift`, `EsignSourceKey.swift` | Ksign source handling | reuse | P2 | BUILD |
| A03 | Add source by URL, with validation feedback | COMPLETE | `Feather/Views/Sources/SourcesAddView.swift`, `SourcesViewModel.swift` | Feather `Views/Sources` | keep | P2 | BUILD |
| A04 | Import / export source list | COMPLETE | `Views/Odysseus/Settings/ODSettingsView.swift` → `ODSourceListTransferView` | Feather source export | keep | P3 | BUILD |
| A05 | Add source by QR code | COMPLETE | `Views/Odysseus/Sources/ODQRScannerView.swift` | Feather QR flow | keep | P3 | NONE |
| A06 | Scheduled + manual refresh | COMPLETE | `SourcesViewModel.fetchSources`, `ODCatalogStore.refreshIfNeeded`, `ODPrefs.sourceAutoRefreshHours` | Feather `SourcesViewModel` | keep; see BUG-011 for the concurrency guard | P2 | BUILD |
| A07 | Source caching / offline snapshots | **MISSING** | — (`SourcesViewModel.sources` is memory-only) | Feather `Storage+SourceMetadata` (provenance, not caching) | new: disk cache of last-good `ASRepository` | P1 | NONE |
| A08 | Source health monitoring | PARTIAL | `Backend/Observable/SourceFetchErrorToastCenter.swift` | — | adapt: persist per-source status + last error | P2 | NONE |
| A09 | Duplicate source detection | PARTIAL | `Storage+Sources.swift:sourceExists(_:)` (identifier only) | — | adapt: normalise URL, compare both identifier and host/path | P2 | NONE |
| A10 | Invalid source handling | PARTIAL | `ASRepository` throws on decode; `SourcesAddView` shows the error | — | adapt: keep the source with an error state instead of dropping it | P2 | NONE |
| A11 | Source error reporting | PARTIAL | Toast only; no history, no per-source retry | — | adapt (A08) | P2 | NONE |
| A12 | Discovery: featured, categories, new/updated, search | COMPLETE | `Views/Odysseus/Discover/ODDiscoverView.swift`, `ODCatalog.swift` | Feather `Views/Library`; Ksign `AppstoreView` | keep | P2 | BUILD |
| A13 | Cross-source duplicate grouping | COMPLETE | `ODCatalog.build` (keys on lowercased bundle ID when enabled) | — | keep | P2 | NONE |
| A14 | App update detection | **MISSING** | — | RyukSign `AppUpdateChecker.swift`; Feather `UpdateManager.swift` | adapt (ODY-302) — see `ODYSSEUS_IMPLEMENTATION_ROADMAP.md` | P1 | NONE |
| A15 | Source prioritisation | PARTIAL | `ODCatalog.build` picks newest `currentDate`; no user preference | — | adapt: user-ordered source priority | P3 | NONE |
| A16 | Default sources on first launch | COMPLETE | `Backend/Services/DefaultSourceInstaller.swift`, `Resources/DefaultSources.json` | Feather defaults | keep, but review the three live third-party endpoints (threat T4) | P1 | BUILD |

---

## B. Signing and certificate management

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| B01 | `.p12` import | COMPLETE | `Utilities/Handlers/CertificateFileHandler.swift`, `Views/Settings/Certificates/*` | Feather `CertificateFileHandler` | keep; fix storage protection (S-03) | P0 | BUILD |
| B02 | `.mobileprovision` import and decode | COMPLETE | `Utilities/CertificateReader/CertificateReader.swift` | Feather `CertificateReader` | keep | P0 | BUILD |
| B03 | P12 password verification | COMPLETE | `FR.checkPasswordForCertificate` → `p12_password_check` (Zsign) | Feather `FR` | keep | P1 | NONE |
| B04 | Certificate chain / key validation | PARTIAL | `CertificateReader` decodes fields; no chain or key-pair check | — | new: validate key matches cert, chain terminates in Apple WWDR | P1 | NONE |
| B05 | Expiry tracking and reminders | COMPLETE | `CertificatePair.expiration`, `ODExpiryPill`, `ODExpiryReminderScheduler` | — | keep | P2 | BUILD |
| B06 | OCSP revocation checking (parse, verify, authorise, freshness) | COMPLETE | `Backend/Certificates/ODOCSPChecker.swift`, `ODOCSPCore.swift`, `ODX509.swift`, `ODDER.swift`, `ODCertificateStatusStore.swift` | — (original) | keep — this is Odysseus's strongest module | P0 | UNIT |
| B07 | Apple ID sign-in, 2FA, anisette | COMPLETE | `Backend/AppleID/ODAppleIDManager.swift`, `SideSign/` | SideStore/Catalyst `SideSign` | keep (AGPL boundary) | P0 | NONE |
| B08 | Apple ID team/cert/device/App-ID/profile operations | COMPLETE | `SideSign/Sources/*`, `ODAppleIDManager` | SideStore `SideSign` | keep | P1 | NONE |
| B09 | Multiple identities and default selection | COMPLETE | `ODPrefs.defaultCertificate`, `ODSignPipeline.defaultIdentity` | Feather selection | keep | P1 | BUILD |
| B10 | Bundle-ID prefix / suffix | COMPLETE | `ODPrefs.adjustedBundleID`, `Views/Odysseus/Settings/ODSettingsView.swift` | — | keep | P2 | NONE |
| B11 | PPQ protection | COMPLETE | `OptionsManager.ppq*`, `ODSignPipeline.defaultOptions` | Feather PPQ | keep — note the random suffix blocks identifier-based matching later (ODY-302) | P2 | NONE |
| B12 | Certificate export (`.p12` + password) | **BROKEN** | `FR.exportCertificateAndOpenUrl` (`FR.swift:164–223`) | Feather export | fix BUG-001 + S-01 before any release | P0 | NONE |
| B13 | Certificate import via `odysseus://` | COMPLETE | `FeatherApp._handleURL` (`FeatherApp.swift:97–144`) | Feather deep links | harden (S-02): confirm with the user, require unlocked device | P0 | NONE |
| B14 | Certificate deletion | PARTIAL | `Storage+Certificate.swift:46–52` | Feather | fix BUG-005 (silent orphaned p12) | P2 | NONE |
| B15 | Secret storage (keychain) | PARTIAL | `ODKeychain.swift` (Apple ID only); `CertificatePair.password` is Core Data | — | new: move p12 passwords to keychain (S-03) | P0 | NONE |
| B16 | Structured signing diagnostics | PARTIAL | `Logger++`, `ODDiagnosticsView` | RyukSign `SigningLog.swift` | adapt: per-signing run record | P2 | NONE |
| B17 | Signing failure recovery / retry | PARTIAL | `ODSignPipeline.signAndInstall` alert only | RyukSign `InstallQueue` | adapt later (ODY-203) | P2 | NONE |
| B18 | Apple ID certificate export with Face ID | COMPLETE | `Views/Odysseus/Settings/ODAppleIDView.swift:310–316` | — | keep; use the same gate for B12 | P1 | NONE |

---

## C. IPA inspection and signing pipeline

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| C01 | IPA / TIPA import | COMPLETE | `Utilities/Handlers/AppFileHandler.swift` | Feather `AppFileHandler` | keep | P0 | BUILD |
| C02 | ZIP validation before extraction | **MISSING** | `AppFileHandler.extract()` unzips on extension alone | — | new: size/entry/ratio limits before unzip | P1 | NONE |
| C03 | Path-traversal protection on extraction | NEEDS_INVESTIGATION | delegated to `Zip.unzipFile` (marmelroy/Zip) | — | verify library behaviour; add own post-extraction path audit | P1 | NONE |
| C04 | App metadata extraction | COMPLETE | `AppFileHandler.addToDatabase`, `Bundle` extensions | Feather | keep | P1 | NONE |
| C05 | Info.plist parsing and modification | COMPLETE | `SigningHandler._modifyDict` | Feather `SigningHandler` | keep; generalise into an editor later (ODY-401) | P1 | NONE |
| C06 | Entitlements inspection | PARTIAL | none in-app; Zsign consumes a file | RyukSign `MachOEntitlements.swift`, `EntitlementsManager.swift` | adapt (ODY-202) | P2 | NONE |
| C07 | Entitlements modification | PARTIAL | `Options.appEntitlementsFile` → `ZsignHandler` `entitlementsPath` | RyukSign entitlements editor | adapt (ODY-401) | P2 | NONE |
| C08 | Mach-O inspection | PARTIAL | `Utilities/MachO/MachOUtils.m` (fixups only) | RyukSign `MachOReader.swift` | adapt if entitlements UI lands | P3 | NONE |
| C09 | Architecture detection | PARTIAL | arm64e/SDK-26 fixup path only | RyukSign `MachOReader` | adapt | P3 | NONE |
| C10 | Framework / dylib discovery and injection | COMPLETE | `TweakHandler.swift`, `Views/Signing/Shared/Signing{Frameworks,Dylib}View.swift` | Feather `TweakHandler` | keep | P2 | NONE |
| C11 | Nested code-signing order (frameworks, plugins) | NEEDS_INVESTIGATION | inside `Zsign` submodule | Zsign | verify against a fixture with frameworks + extensions | P1 | NONE |
| C12 | Extension signing and injection | COMPLETE | `SigningHandler` `$0.hasSuffix(".appex")`, `Options.injectIntoExtensions` | Feather | keep | P2 | NONE |
| C13 | Watch app handling | PARTIAL | `SigningHandler._removeWatchIfNeeded` — removes `Watch/` | Feather | decide: remove (current) vs sign; document | P3 | NONE |
| C14 | App-group / shared-container handling | **MISSING** | — | — | new, only if device installs demand it | P3 | NONE |
| C15 | Provisioning profile embedding | COMPLETE | `ZsignHandler.sign` (`provisionPath`) | Zsign | keep | P0 | NONE |
| C16 | Bundle-ID modification | COMPLETE | `SigningHandler` + `Options.appIdentifier` | Feather | keep | P1 | NONE |
| C17 | Entitlement compatibility validation | **MISSING** | — | — | new: reject entitlements the profile cannot grant | P2 | NONE |
| C18 | Post-sign signature verification | PARTIAL | `ZsignHandler.swift:121–130` — `checkSigned` is a presence check | Zsign | add real `codesign`-equivalent verification (ODY-201) | P1 | NONE |
| C19 | In-app final IPA validation | **MISSING** | CI-only `scripts/verify_ipa.sh` | — | new: reuse the script's checks in-app | P2 | NONE |
| C20 | Temporary-file cleanup | PARTIAL | `try? await handler.clean()`; `FeatherDownloads/` not swept | — | adapt: startup sweep + explicit cleanup | P2 | NONE |

---

## D. Installation and sideloading

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| D01 | Semi-local HTTP server install | COMPLETE | `Backend/Server/ServerInstaller.swift`, `ServerInstaller+Compute.swift` | Feather/Lakr `Server` | keep; LAN exposure is S-04 | P0 | NONE |
| D02 | Fully-local install with user TLS identity | COMPLETE | `Backend/Server/ODLocalServerTLS.swift`, `ServerInstaller+TLS.swift` | — | keep | P1 | NONE |
| D03 | Pairing-file / IDevice install | COMPLETE | `FR.movePairing`, `HeartbeatManager`, `IDeviceKitten` (submodule) | idevice; RyukSign | keep | P1 | NONE |
| D04 | LocalDevVPN integration | PARTIAL | `Info.plist` `LSApplicationQueriesSchemes`, deep link | SideStore `LocalDevVPN` | keep; document prerequisites | P2 | NONE |
| D05 | Install progress UI | COMPLETE | `Views/Odysseus/Install/ODInstallSheet.swift`, `InstallerStatusViewModel` | Feather | keep | P2 | NONE |
| D06 | Install failure handling | PARTIAL | `InstallerStatusViewModel.status = .broken` + sheet | RyukSign `InstallCleanup` | adapt: retry + diagnostics | P1 | NONE |
| D07 | Device compatibility checks | **MISSING** | — | — | new: minimum-OS and device-family check from the profile | P2 | NONE |
| D08 | Installed-app detection | **MISSING** | only `UIApplication.openApp(with:)` for signed apps | — | new: `LSApplicationWorkspace`-free approach or user confirmation | P3 | NONE |
| D09 | Reinstall / update-in-place | PARTIAL | system `itms-services` behaviour, unchanged | — | verify on device; otherwise out of scope | P2 | NONE |
| D10 | App removal from device | **MISSING** | library delete only | — | investigate (needs device services) | P3 | NONE |
| D11 | Install history | **MISSING** | — | — | new | P3 | NONE |
| D12 | Install diagnostics | PARTIAL | OSLog lines only | RyukSign `SigningLog` | adapt | P2 | NONE |

---

## E. App library and management

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| E01 | Signed / Downloaded / Imported separation | COMPLETE | `ODLibraryView`, `ODDownloadOrigin` (`ODSignPipeline.swift:427–440`) | Feather `LibraryView` | keep; fix unbounded list growth (BUG-013) | P2 | BUILD |
| E02 | Metadata display (name, identifier, version, icon) | COMPLETE | `ODLibraryView._row`, `FRAppIconView` | Feather | keep | P2 | BUILD |
| E03 | Version display | COMPLETE | same | Feather | keep | P2 | BUILD |
| E04 | Signing identity shown per app | COMPLETE | `_signedPills`, `ODAppleIDSignedApps` | — | keep | P2 | NONE |
| E05 | Certificate / profile expiry shown | COMPLETE | `ODExpiryPill`, `ODCertificateStatusStore` | — | keep | P2 | NONE |
| E06 | Revocation badge | COMPLETE | `ODOCSPPill`, `ODCertificateCards` | — | keep | P2 | UNIT |
| E07 | Update availability | **MISSING** | — | RyukSign, Feather | adapt (ODY-302) | P1 | NONE |
| E08 | Duplicate detection inside the library | **MISSING** | — | — | new | P3 | NONE |
| E09 | Backup / restore of signed apps and certs | **MISSING** | — | RyukSign `BackupManager`/`BackupCrypto`; SideStore `SideBackup` | adapt one (ODY-403) | P3 | NONE |
| E10 | Export / "Save a Copy" IPA | COMPLETE | `ArchiveHandler`, `ODInstallSheet` archive mode | Feather `ArchiveHandler` | keep | P2 | NONE |
| E11 | Delete with quarantine + restore-on-failure | COMPLETE | `Storage+Shared._deleteRecord` | — | keep — do not regress | P0 | UNIT |
| E12 | Filtering (scope + search) | COMPLETE | `ODLibraryView._matches`, `Scope` | Feather | keep | P3 | NONE |
| E13 | Sorting | PARTIAL | date-descending only | Feather | adapt: name/version/expiry | P3 | NONE |
| E14 | Batch operations on the library | **MISSING** | — | RyukSign `BatchJobRunner` | adapt (ODY-402) | P3 | NONE |

---

## F. Advanced features and customisation

| # | Feature | Status | Existing file(s) | Upstream reference | Integration strategy | Priority | Evidence |
|---|---|---|---|---|---|---|---|
| F01 | Tweak injection (`.dylib`, `.framework`, `.bundle`) | COMPLETE | `TweakHandler.swift`, `Views/Signing/Shared/*` | Feather | keep | P2 | NONE |
| F02 | `.deb` support and extraction | COMPLETE | `TweakHandler` + `Utilities/ARDecompression/AR.swift` | Feather; RyukSign `TweakExtractor` | keep; fix BUG-007 crash path | P2 | NONE |
| F03 | ElleKit / CydiaSubstrate switch | COMPLETE | `Options.experiment_replaceSubstrateWithEllekit` | Feather | keep | P3 | NONE |
| F04 | Inject into app extensions | COMPLETE | `Options.injectIntoExtensions`, `TweakHandler` | Feather | keep | P3 | NONE |
| F05 | Entitlements editor | PARTIAL | file-picker option only | RyukSign `Views/Signing/Entitlements/*` | adapt (ODY-401) | P2 | NONE |
| F06 | Info.plist editor (diff / raw) | **MISSING** | only hard-coded toggles | RyukSign `InfoPlistPlan.swift`, `PlistDiff.swift` | adapt (ODY-401) | P2 | NONE |
| F07 | App-icon customisation | COMPLETE | `SigningHandler.appIconData`, `SigningAlternativeIconView` | Feather | keep | P3 | NONE |
| F08 | Themes / tint / appearance | COMPLETE | `ODTheme`, `Views/Settings/Appearance/*` | — | keep | P3 | NONE |
| F09 | Liquid Glass / SDK-26 compatibility | PARTIAL | `Options.experiment_supportLiquidGlass`, `MachOUtils.m` | LiveContainer Mach-O fixups (Apache-2.0) | keep; needs device verification | P2 | NONE |
| F10 | Localisation | PARTIAL | `Feather/Resources/Localizable.xcstrings` (276 keys, **en only**), 741 `.localized(` call sites | Feather (also English-only) | adapt: 741 keys are extracted but only 276 exist — reconcile, then add one locale at a time | P4 | NONE |
| F11 | Diagnostics and log export | COMPLETE | `ODDiagnosticsView` (`OSLogStore`), `Logger++` | RyukSign `FileLogger` | keep | P3 | NONE |
| F12 | Crash / error reporting | **MISSING** | — | RyukSign `FileLogger`/`StdoutCapture` | new, opt-in and local-first | P4 | NONE |
| F13 | Accessibility | **MISSING** | 2 `accessibilityLabel` uses in 16.8k lines | — | new: labels, Dynamic Type, contrast | P4 | NONE |
| F14 | iPad layout | COMPLETE | `ODRootView` sidebar branch | — | keep | P3 | NONE |

---

## G. LiveContainer-class execution research

These are recorded so they are not re-litigated in later planning. Details and evidence: `UPSTREAM_SOURCE_REGISTER.md` §2.6 and `ODYSSEUS_ARCHITECTURE_AUDIT.md` §9.

| # | Capability | Status | Why | Priority |
|---|---|---|---|---|
| G01 | Run apps without installing them | **UNSUPPORTED** | Requires in-process guest execution plus entitlements the app does not carry | — |
| G02 | Guest Mach-O patching (`__PAGEZERO`, `MH_EXECUTE`→`MH_DYLIB`, `_NSGetExecutablePath`) | **UNSUPPORTED** | Only the small signing-time fixup subset is portable; that part is already ported (F09) | — |
| G03 | 128 keychain access groups / multi-account | **UNSUPPORTED** | Verified 128 groups in upstream `entitlements.xml`; a sideloaded profile cannot grant them | — |
| G04 | Multitasking / virtual windows | **UNSUPPORTED** | Depends on G01 and SpringBoard behaviour | — |
| G05 | App extensions inside the container | **UNSUPPORTED** | Upstream limitation, documented in its README | — |
| G06 | Tweak loader injected into every guest app | **UNSUPPORTED** | Depends on G01 | — |
| G07 | Pairing-file helpers (FlekDeck `IdevicePairing`) | **NEEDS_INVESTIGATION** | Possibly reusable without the container; must be checked against the existing `IDeviceKitten` path first | P4 |
| G08 | Guest isolation / sandboxing | **UNSUPPORTED** | Upstream states guest containers are not sandboxed from each other — unacceptable as-is | — |

---

## H. Security and reliability

| # | Feature | Status | Existing file(s) | Default risk | Priority | Evidence |
|---|---|---|---|---|---|---|
| H01 | Keychain protection for Apple ID secrets | COMPLETE | `ODKeychain.swift` (`AfterFirstUnlockThisDeviceOnly`) | return codes ignored (BUG-006) | P1 | NONE |
| H02 | Private-key material at rest | PARTIAL | p12 in `Documents/Feather/Certificates/…` with no protection; password in Core Data | S-03 | P0 | NONE |
| H03 | Log redaction | PARTIAL | no `privacy:` annotations anywhere; no secrets are logged (verified by grep) | S-11 | P2 | NONE |
| H04 | Secure temporary storage | PARTIAL | Apple ID material and the TLS identity: 0600/0700 + protection + backup-excluded; certificate store and download/temp dirs: defaults | S-03 | P1 | NONE |
| H05 | Archive extraction safety | NEEDS_INVESTIGATION | delegated to `Zip`; no own checks | S-05 | P1 | NONE |
| H06 | URL / deep-link validation | PARTIAL | six handlers, no caller authentication | S-01, S-02 | P0 | NONE |
| H07 | Network security | PARTIAL | ATS exceptions for Apple hosts only; LAN install server in plaintext | S-04 | P1 | NONE |
| H08 | Source trust boundary | PARTIAL | any added source is trusted for IPA URLs | T4 | P1 | NONE |
| H09 | Certificate validation | PARTIAL | fields parsed, chain not validated | B04 | P1 | NONE |
| H10 | Dependency security | PARTIAL | no root `Package.resolved`; SideSign deps pinned to branches | S-08 | P1 | NONE |
| H11 | Error recovery | PARTIAL | alerts for signing; silent for downloads/cert delete | BUG-002/003/005 | P1 | NONE |
| H12 | Data consistency | COMPLETE | snapshot discipline, background contexts, quarantine | — | P0 | UNIT |
| H13 | Memory management | PARTIAL | audio-engine node leak (BUG-009); retain-cycle scan clean | — | P3 | NONE |
| H14 | Background execution | PARTIAL | dynamic `BGTaskScheduler.register` after launch (BUG-004) | — | P1 | NONE |
| H15 | Resource cleanup | PARTIAL | `try?` cleanup paths; temp dirs accumulate | — | P2 | NONE |
| H16 | Sensitive data in device backups | NEEDS_INVESTIGATION | Core Data + `Documents/` are backed up unless excluded | S-03 | P1 | NONE |

---

## I. Aggregate view

| Group | Rows | COMPLETE | PARTIAL | BROKEN | MISSING | UNSUPPORTED | NEEDS_INVESTIGATION |
|---|---|---|---|---|---|---|---|
| A Sources | 16 | 9 | 5 | 0 | 2 | 0 | 0 |
| B Certificates | 18 | 12 | 5 | 1 | 0 | 0 | 0 |
| C Pipeline | 20 | 7 | 7 | 0 | 4 | 0 | 2 |
| D Install | 12 | 4 | 4 | 0 | 4 | 0 | 0 |
| E Library | 14 | 9 | 1 | 0 | 4 | 0 | 0 |
| F Advanced | 14 | 8 | 3 | 0 | 3 | 0 | 0 |
| G Container | 8 | 0 | 0 | 0 | 0 | 7 | 1 |
| H Security | 16 | 2 | 12 | 0 | 0 | 0 | 2 |
| **Total** | **118** | **51** | **37** | **1** | **17** | **7** | **5** |

Interpretation: Odysseus is not a shallow shell — 51 capabilities are end-to-end, including the hardest one (revocation) — but only **four rows** carry unit-test evidence (all in storage and revocation) and **zero rows** are device-verified, and the credential-handling gaps in group H are release blockers regardless of feature count. Priority therefore follows `ODYSSEUS_IMPLEMENTATION_ROADMAP.md` (security first, then signing correctness, then features), not the count above.
