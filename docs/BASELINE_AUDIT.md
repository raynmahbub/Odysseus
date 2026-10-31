# Odysseus baseline source audit (re-verified)

**Audit date:** 2026-10-31 (UTC)
**Audited revision:** `2a54e3bfaa7749e047f5ab14477bcc6501b24f6d` (`fix(ios): replace deprecated SwiftUI onChange handlers`)
**Current working revision:** `c2040b04f22f6eaab67211f3a5cd62aad91970c3` (`docs(audit): map upstream feature compatibility and integration plan`)
**Working branch:** `arena/b50aa4f2-odysseus` (== `master`; see §0.1 — the branch and hash named in the first issue of this audit are stale)
**Previous audit:** `docs/BASELINE_AUDIT.md` at revision `2664dadedf9aca36fda0925a8aada92e2c79323f`, branch `arena/438d62e5-odysseus`
**Scope:** re-establish the current app, architecture, implementation state, build evidence, and highest-risk defects against the **current** working tree before feature integration. Static source audit plus review of the existing GitHub Actions result. Not an iOS device-security certification.

> **How to read this file.** Every finding below is tagged **RECHECKED** (re-examined against the current tree), **NEW** (first recorded here), or **STALE** (present in the previous audit but no longer true / no longer present). The previous audit is preserved verbatim in [Appendix A](#appendix-a-previous-audit-2664dad).
>
> **Baseline caveat.** Findings were re-examined at `2a54e3b`. Since then the history was squashed; the tree is now `c2040b0`. §0.1 proves that every path outside `docs/` is byte-identical between the two revisions, so the findings carry over. Where a finding is a *claim about the build*, §6 records the CI run instead of an assumption.

---

## 0. Repository state — verified at `c2040b0`

| Fact | Value | Status |
|---|---|---|
| Root | `/home/user/Odysseus` | RECHECKED |
| Remote | `https://github.com/raynmahbub/Odysseus.git` (`origin`) | RECHECKED |
| HEAD | `c2040b04f22f6eaab67211f3a5cd62aad91970c3` | **NEW — corrected** |
| `master` | `c2040b04…` (identical to HEAD and to `origin/master`) | **NEW — corrected** |
| Working branch | `arena/b50aa4f2-odysseus` | **NEW — corrected** |
| Audited revision | `2a54e3bf…` — no longer a reachable commit object in this clone | **NEW** |
| Working tree | clean (`git status --porcelain` empty) | RECHECKED |
| History depth | **single commit** — the repository was squashed/imported twice; `git log` shows one commit | NEW |
| Tag | `nightly` → `2a54e3b` exists on the remote; the local clone carries **no tags** | **NEW — corrected** |
| Submodules pinned | `Zsign` @ `6ffe703df73ef9069adacdbb19d571f11a69a801` (`khcrysalis/Zsign-Package`, branch `package`); `IDeviceKitten` @ `837cf1e14d4875771dd5ee1b754a4c86215c5db3` (`khcrysalis/IDeviceKit`) | RECHECKED |
| Submodules initialized | **NO** — both submodule working trees are empty in this checkout (`git submodule status` shows `-`) | NEW |

**Consequence:** a local `xcodebuild` in this sandbox is impossible twice over — the checkout is Linux (no `xcodebuild`, no `swiftc`), and the two git submodules are not populated. CI populates them with `submodules: recursive`.

### 0.1 Baseline identity — how `2a54e3b` and `c2040b0` relate

The repository history was squashed when this sandbox was created, so the audited commit is no longer reachable locally and `arena/088597d5-odysseus` (still on the remote as `fe0f37e`) is not the tree that will be modified. The *content* is unchanged:

| Check | Result |
|---|---|
| `git rev-parse HEAD:Feather` | `c996af8e9f653ea3e668558371bd0e4603516f22` |
| `gh api repos/raynmahbub/Odysseus/git/trees/2a54e3b` → `Feather` | `c996af8e9f653ea3e668558371bd0e4603516f22` |
| Top-level paths compared | 27 of 27; **only `docs/` differs** |

So this audit is valid for the code at `c2040b0`. `docs/` differs because this audit package was added on top of the audited tree. Re-verified in this session against the current tree: entitlements contain only `get-task-allow`; the test target holds 16 cases in 6 files; both submodules are empty; `DefaultSources.json` still ships three live third-party sources plus placeholders; `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `CODE_SIGN_STYLE = Manual`, bundle ID `com.mirazbakis.Odysseus`.

The full disposition of the five review points raised against this package (branch/baseline, counts and statuses, the data-model check, per-file licensing, and Batch 1 approval) is recorded in [`BATCH1_READINESS_REVIEW.md`](BATCH1_READINESS_REVIEW.md).

## 1. Project shape

- **One Xcode application target**, internally named `Feather`, product/display name `Odysseus`.
- **One shared scheme** `Feather`. `Feather.xcworkspace` + `Feather.xcodeproj`.
- **Deployment target:** `IPHONEOS_DEPLOYMENT_TARGET = 17.0`; `TARGETED_DEVICE_FAMILY = "1,2"` (iPhone + iPad). Mac Catalyst is enabled in the project and `Makefile` has a Catalyst target, but **CI only builds the iOS IPA**.
- **Swift:** `SWIFT_VERSION = 5.0` (project-level). SideSign's own package uses `swift-tools-version: 6.0` with `swiftLanguageModes: [.v6]`.
- **Bundle ID:** `com.mirazbakis.Odysseus` (+ `$(FEATHER_DISAMBIGUATOR)` disambiguator at build).
- **Code signing:** `CODE_SIGN_STYLE = Manual`; `DEVELOPMENT_TEAM` in the *project* is `566RT33SA2`, the *target* is empty (`""`); the Makefile builds with `CODE_SIGNING_ALLOWED=NO` and adhoc-signs the payload.
- **Entitlements:** `Feather/Supporting Files/Feather.entitlements` contains **only `get-task-allow`** (verified). See §7.
- **Test target:** present — `com.mirazbakis.OdysseusTests` (`OdysseusTests/`), `TEST_HOST`/`BUNDLE_LOADER` wired to the app; 16 XCTest cases across 6 files. **This is NEW since the previous audit** (which reported "no test sources").

### Dependencies

Local Swift packages (vendored in-repo): `AltSourceKit`, `NimbleKit`, `Zsign` (submodule), `IDeviceKitten` (submodule), `SideSign` (vendored under `SideSign/`, from SideStore/Catalyst).

Remote SPM packages (declared in `project.pbxproj`, **no root `Package.resolved`**): `vapor`, `Nuke`, `Zip`, `SWCompression`, `LicensePlist`, `BitByteData`.

`SideSign/Package.swift` pulls: `apple/swift-crypto` (exact 4.3.1), `mahee96/CodeSignKit` (branch `main`), `mahee96/GSACryptoKit` (branch `main`), `SideStore/libdeflate` (branch `master`), `mahee96/AnisetteKit` (branch `main`). `SideSign/Package.resolved` pins revisions but the app consumes SideSign as a local package, so the *root* build is not locked.

`license_plist.yml` documents third-party licenses (idevice MIT, Zsign, ElleKit, SideSign AGPL-3.0, LiveContainer via `Zsign/LICENSE_LC`).

## 2. Module map (current tree)

| Concern | Paths | Notes |
|---|---|---|
| App entry / lifecycle / URL schemes | `Feather/FeatherApp.swift`, `AppDelegate` | `odysseus://` schemes: `select-certificate`, `switch-certificate`, `import-certificate`, `export-certificate`, `source/<url>`, `install/<url>`; file-type handlers for `.ipa`/`.tipa` |
| Storefront / catalog | `Feather/Views/Odysseus/Discover/*`, `Feather/Views/Odysseus/ODRootView.swift`, `ODCatalogStore.swift`, `ODCatalog.swift` | Discover (featured / New & Updated / Recently Added / Categories / Sources / search); iOS 18+ TabView + search tab; iPad sidebar; iOS 26 liquid-glass tab bar |
| Sources | `Feather/Views/Sources/*`, `Feather/Backend/Storage/Storage+Sources.swift`, `Feather/Backend/Services/DefaultSourceInstaller.swift`, `AltSourceKit` | AltStore/ESign sources; add by URL or QR; import/export; auto-refresh; default sources from `Resources/DefaultSources.json` |
| Library | `Feather/Views/Odysseus/Library/ODLibraryView.swift`, `ODCertificateCards.swift`, `Feather/Views/Library/*`, `Storage+Imported.swift`, `Storage+Signed.swift` | Signed / Downloaded / Imported; expiry pills; certificate revocation cards |
| Signing pipeline | `Feather/Backend/Odysseus/ODSignPipeline.swift`, `Feather/Utilities/FR.swift`, `Feather/Utilities/Handlers/{SigningHandler,ZsignHandler,TweakHandler,AppFileHandler,ArchiveHandler,CertificateFileHandler}.swift` | One route: pick identity (cert or Apple ID) → revocation gate → bundle-ID adjust → zsign → install. Strongest existing seam. |
| Apple ID signing | `Feather/Backend/AppleID/ODAppleIDManager.swift`, `ODKeychain.swift`, `Views/Odysseus/Settings/ODAppleIDView.swift`, vendored `SideSign/` | Login + 2FA, anisette, team/cert/device/AppID/profile, p12 export |
| OCSP revocation | `Feather/Backend/Certificates/ODOCSP*.swift`, `ODX509.swift`, `ODDER.swift`, `ODCertificateStatusStore.swift`, `ODCertificateStatusStore` + tests | Custom RFC 6960 client + DER parser; freshness + responder-authorization checks |
| Installation | `Feather/Backend/Server/ServerInstaller*.swift`, `ODLocalServerTLS.swift`, `Feather/Views/Odysseus/Install/ODInstallSheet.swift`, `Feather/Views/Library/Install/InstallPreviewView.swift`, IDevice pairing path | Semi-local (default) + fully-local (TLS identity) server; pairing-file + LocalDevVPN path |
| Persistence | `Feather/Backend/Storage/Storage*.swift`, `Feather.xcdatamodeld/` | Core Data; main-actor view context; background contexts for writes; quarantine/restore on delete |
| Preferences | `Feather/Backend/Odysseus/ODPrefs.swift`, `Feather/Backend/Observable/OptionsManager.swift` | Settings keys centralized in `ODPrefs`; signing `Options` struct |
| Diagnostics | `Feather/Views/Odysseus/Settings/ODDiagnosticsView.swift`, `Feather/Extensions/Logger++.swift`, `Feather/Utilities/FileLogger.swift`? (not present) | OSLog + log export |
| Tweaks / customization | `Feather/Utilities/Handlers/TweakHandler.swift`, `Feather/Views/Signing/*`, `Feather/Utilities/ARDecompression/*`, `Feather/Utilities/CertificateReader/*`, `Feather/Utilities/MachO/MachOUtils.m` | dylib/deb/framework/bundle injection; ElleKit; Liquid Glass + arm64e Mach-O fixups (ported from LiveContainer, Apache-2.0) |
| Tests | `OdysseusTests/*.swift` | Zsign outcome, OCSP core/freshness/responder-auth, Core Data concurrency, Apple ID material cleanup |

## 3. Feature presence vs proof

`Source status` is deliberately narrow: **`Code present`** means the code exists and is reachable; it does **not** mean tested, and it never means device-verified. `Absent` means there is no implementation. Test and build evidence are tracked separately (`SOURCE_INTEGRATION_MATRIX.md` status model, §6 below).

| Capability | Source status | Evidence / gaps |
|---|---|---|
| Discover storefront, search, categories, featured/recent rows, duplicate grouping | Code present | `ODDiscoverView`, `ODCatalog`. No catalog unit tests. Not exercised on-device. |
| Sources: add/import/export, QR, auto-refresh, default sources | Code present | `SourcesAddView`, `ODQRScannerView`, `SourcesViewModel`, `DefaultSourceInstaller`. No retry/failure tests. |
| Import IPA/TIPA, library organization, expiry pills | Code present | `AppFileHandler`, `ODLibraryView`. Not exercised on-device. |
| Sign with `.p12` + `.mobileprovision` (Zsign) | Code present | `ZsignHandler` + `ODZsignOutcome.validate`. Build success ≠ every sign result valid. |
| Apple ID signing | Code present | `ODAppleIDManager` + SideSign. Live portal behavior unverified. |
| OCSP status, notifications, expiry reminders, revoked policy | Code present | `ODOCSP*` + tests for parser/freshness/authz. Live Apple interoperability unverified. |
| Local server + pairing install | Code present | `ServerInstaller*`, IDevice path. No device result in this audit. |
| Tweaks & app customization | Code present (Feather-derived) | `TweakHandler`, `SigningHandler` modifications. |
| App update checker | **Absent** | Upstream Feather has `Backend/Observable/UpdateManager.swift` + `Storage+SourceMetadata.swift`; RyukSign has `AppUpdateChecker`. Odysseus does not. Candidate. |
| Bulk/batch signing | **Absent** | Ksign `BulkSigningView`; RyukSign `BatchJobRunner`/`BatchSignView`. Candidate. |
| File manager / hex/plist editor | **Absent** | Ksign `Views/Files/*`. Candidate. |
| Web/WebDAV file transfer server | **Absent** | RyukSign `WebManagerServer*`. Candidate. |
| Live Activities / Dynamic Island download progress | **Absent** | RyukSign `DownloadManager+LiveActivity.swift`. Candidate. |
| App container / live app hosting | **Absent** (only Mach-O fixup ported) | LiveContainer / FlekDeck. Separate feasibility workstream (§7). |
| SideStore refresh / untethered install | **Absent** | SideStore. Large integration; see matrix. |

## 4. Findings — status at `2a54e3b`

Severity is a prioritization aid, not a formal CVSS score.

### 4.1 Critical — shared TLS private key packaging — **RECHECKED / RESOLVED**

The previous audit reported that `Makefile` downloaded `backloop.dev/pack.json` and bundled `.key1`/`.key2` as `deps/server.pem`, copied into the app and IPA.

**Current state: RESOLVED.** The current `Makefile` no longer downloads any pack; the `clean` target removes `deps cert.json`. `ODLocalServerTLS.removeLegacySharedMaterial()` runs at launch and removes legacy `Documents/server.pem`/`server.crt`/`commonName.txt`. Fully Local mode now requires the user to import a matching certificate chain + private key + hostname (`ODLocalServerTLS`, `ServerView`). Semi Local (default) needs no TLS private key in-app.

**Residual:** the old endpoint was never fetched during the previous audit, so the status of any formerly-distributed key is unknown. The repo no longer ships it, but that does not revoke copies already distributed. Owner must rotate/revoke if real.

### 4.2 High — IPA bundle modified after code-signing — **RECHECKED / RESOLVED**

Previously `codesign` ran, then resources were copied into the `.app`, invalidating the seal. **Current `Makefile` copies the app into `Payload/` and *then* adhoc-signs**; `scripts/verify_ipa.sh` runs in CI after packaging. **RESOLVED.**

### 4.3 High — Core Data view-context accessed from detached work — **RECHECKED / RESOLVED**

`Storage` is `@MainActor`; `addImportedAsync`/`addSignedAsync` write on private background contexts; only permanent object IDs and value snapshots cross queues. `StorageConcurrencyTests` covers concurrent background writes. **RESOLVED.**

### 4.4 High — Zsign failures reported as success — **RECHECKED / RESOLVED**

`ODZsignOutcome.validate(returned:callbackSuccess:callbackError:)` requires the Boolean return, the callback, callback success, and (separately) a `checkSigned` presence check before the app is moved into Library storage. `ODZsignOutcomeTests` covers true/false/missing/error paths. **RESOLVED.** Note: `Zsign.checkSigned` is a *presence* check, not cryptographic verification — still true.

### 4.5 High — OCSP "good" could outlive verification — **RECHECKED / RESOLVED**

`ODOCSPResult.isFresh(...)` now requires `signatureVerified` and validates `checkedAt`, `producedAt`, `thisUpdate`, and `nextUpdate` against the current time. `ODOCSPFreshnessTests` and `ODOCSPResponderAuthorizationTests` cover stale/bad-signature/delegated-responder cases. **RESOLVED** for the code paths tested. Live Apple interoperability remains unverified (§6).

### 4.6 High — Core Data recovery deleted user payloads — **RECHECKED / RESOLVED**

`Storage._loadPersistentStore` surfaces a load failure as `storeLoadError`; it does **not** delete the SQLite store or the `Signed`/`Unsigned`/`Certificates` trees. `FeatherApp` shows a "Library unavailable" screen and gates startup work on `isStoreLoaded`. **RESOLVED.**

### 4.7 Medium — Apple ID signing material not cleaned on failure — **RECHECKED / RESOLVED**

`ODSignPipeline.sign()` uses `defer` to remove the Apple ID temporary directory on success, failure, and cancellation; `ODAppleIDManager.cleanupStaleSigningMaterial()` removes app-owned material older than 24h at startup. `ODAppleIDMaterialCleanupTests` covers stale cleanup. **RESOLVED.**

### 4.8 Medium — "Delete IPA After Signing" default could not be turned off — **RECHECKED / RESOLVED**

`Options.defaultOptions` now initializes `post_deleteAppAfterSigned: false`, aligned with `ODPrefs.autoDeleteIPAs` default `false`. **RESOLVED** for new installs. Existing persisted `Options` are deliberately not migrated (a saved `true` cannot be distinguished from an explicit choice) — documented in `SECURITY_RELIABILITY_REMEDIATION.md`.

### 4.9 Medium — build/runtime validation gaps — **RECHECKED / PARTIALLY RESOLVED**

- **No root `Package.resolved`** — remote package versions are resolved at build time; SideSign's `Package.swift` pins several deps to moving branches. **NEW/ONGOING.**
- **`ServerInstaller._setup()` swallows setup errors** — `make(...)` now captures `startupError` and sets `.broken(error)`, so a failed server setup is surfaced rather than crashing. **RESOLVED** at the `ServerInstaller.make` level; the two install sheets still construct via `make`.
- **Source fetch result appends** — `SourcesAddView` recommended-source results; the previous concern about unstructured `Task { @MainActor }` appends. Needs a re-read of the current `SourcesAddView` to confirm. **TO VERIFY.**
- **`DefaultSources.json` ships live third-party sources** (`fastsign.dev`, `repository.apptesters.org`, `ipa.cypwn.xyz`) plus `ADD_HERESOURCE` placeholder. These are fetched on first launch. **NEW — supply-chain consideration** (see §5).
- **`NSAppTransportSecurity` allows insecure HTTP** for `certs.apple.com`, `crl.apple.com`, `ocsp.apple.com` (OCSP responders are HTTP-only in practice). **NEW — documented.**

### 4.10 NEW — submodules not initialized in this checkout

`Zsign` and `IDeviceKitten` working trees are empty. Any local build must run `git submodule update --init --recursive` first. CI does this via `actions/checkout@v4` `submodules: recursive`. Not a defect in the repo, but a reproduction prerequisite.

### 4.11 NEW — single squashed commit

`git log` shows exactly one commit. This means: no upstream Feather history is available locally for `git cherry-pick`; all Feather-derived changes were imported as a snapshot. Integration planning must treat upstream code as **copy/adapt**, not `git cherry-pick`, unless a history-preserving fork is created.

### 4.12 NEW — no device/account/service validation

No physical-device test has been run for: Fully Local TLS with an owned identity, Semi Local install, pairing install, certificate signing, Apple ID portal flow, or live OCSP against Apple's responder. CI runs simulator unit tests + an unsigned IPA build + `verify_ipa.sh`.

## 5. Security / supply-chain notes (current tree)

1. **Default sources are live third-party endpoints.** First launch installs them automatically. A compromised/malicious default source feeds the Discover catalog and can influence what users install. Consider: removing third-party defaults, or gating them behind an explicit opt-in. **TO DECIDE.**
2. **Insecure HTTP allowed for OCSP/CRL/certs endpoints.** Intentional (Apple's responders are HTTP), but it means ATS is explicitly relaxed for those hosts. Documented.
3. **`get-task-allow` entitlement present.** Required for the install/sign flows. Fully Local server mode needs additional entitlements on iOS 18+ (documented in `HOW_IT_WORKS.md`) that are **not** in `Feather.entitlements`; the registered default is Semi Local.
4. **Certificate export via URL scheme** (`odysseus://export-certificate`) sends the p12 + password to a caller-supplied callback. Guarded by Face ID + warning per `Info.plist` usage string, but the capability is broad. Documented.
5. **No root `Package.resolved`** and branch-pinned SideSign deps → non-reproducible builds.

## 6. Build & validation status

### CI evidence
- Workflow: `.github/workflows/build.yml` — runs on `macos-26`, Xcode `26.4`.
- Steps: checkout (`submodules: recursive`) → `xcodebuild test` (iOS Simulator, iPhone 17) → version → `make iphoneos` → `scripts/verify_ipa.sh` → upload IPA → publish nightly/release.
- The previous audit referenced successful run `37659670246` (2026-10-07) at the older revision.
- **RECHECKED in this session:** run `41198043032` on `master` at `2a54e3b` (2026-10-31T11:43Z) — **success**, job "Build unsigned Odysseus.ipa" (simulator unit tests + IPA build + `scripts/verify_ipa.sh`). The audited code therefore has green CI.
- Run `41219757550` (`arena/088597d5-odysseus`, `fe0f37e`, docs PR #4) — **success**, same job. This is the audit package's own build.
- The squashed `c2040b0` SHA has no CI run of its own (squash-merge did not trigger one on `master`); its only delta from the green tree is `docs/`. Cite the run ids, not the SHA, when asserting a green baseline.

### Checks performed in this audit
- Read the full current source tree (all `Feather/**`, `OdysseusTests/**`, `SideSign/Sources/**`).
- Parsed `project.pbxproj`, `Feather.xcconfig`, `Info.plist`, `Feather.entitlements`, `license_plist.yml`, `Makefile`, `scripts/verify_ipa.sh`, `.github/workflows/build.yml`, `DefaultSources.json`, `app-repo.json`.
- Initialized and cloned upstream reference repos (see `UPSTREAM_SOURCE_REGISTER.md`).
- **Not run (Linux sandbox, no Apple tooling):** `xcodebuild`, `swiftc`, XCTest, `codesign`, `ditto`, IPA verification, SwiftPM resolution/audit.

## 7. LiveContainer-style app container — feasibility note

The current tree **does not** host apps in a container. It only ports a small LiveContainer Mach-O fixup (`Feather/Utilities/MachO/MachOUtils.m`, Apache-2.0, credited to LiveContainer commit `3a029b6`) used to patch SDK-26 / arm64e slices during signing.

LiveContainer itself (`LiveContainer/LiveContainer`, AGPL-3.0) is a fundamentally different architecture: a host executable that patches the guest Mach-O (`__PAGEZERO`, `MH_EXECUTE`→`MH_DYLIB`, `_NSGetExecutablePath` hook, `NSBundle.mainBundle` override, dyld memory loading), `dlopen`s the guest, jumps to its entry point, and runs it in-process. It requires:

- entitlements beyond `get-task-allow`: `com.apple.developer.kernel.increased-memory-limit`, `application-identifier`, healthkit, 128 keychain access groups, app groups;
- a `LiveProcess` helper binary + `LaunchAppExtension`/`ShareExtension`/`MultitaskSupport`/`TweakLoader`/`SideStoreSupport` targets;
- acceptance that guest containers are **not sandboxed** (one guest can read another's data) and that app extensions don't work.

This is a **separate feasibility and security workstream**, not a signing feature. It is **BLOCKED / INVESTIGATE** in the matrix pending an explicit decision; see `ARCHITECTURE.md` §6 and `INTEGRATION_PLAN.md` Batch 8.

## 8. Recommended order (current revision)

1. Keep the existing security remediations green; do not regress the `ODZsignOutcome`/OCSP/Core-Data guarantees.
2. Reconcile the upstream register and feature matrix (`UPSTREAM_SOURCE_REGISTER.md`, `SOURCE_INTEGRATION_MATRIX.md`). **All nine named identities are now resolved:** FeatherPlus is a verified Feather fork with no distinct capability (EXCLUDE); Zeus and FlareStore are closed-source products with no public source repo (concept-reference only); FlekPair source is not published (EXCLUDE).
3. Adopt small, independently reviewable feature batches from Ksign/RyukSign/Feather upstream (update checker, bulk signing, Web/WebDAV transfer, Live Activities, file manager) — see `INTEGRATION_PLAN.md`.
4. Treat LiveContainer/FlekDeck app-container hosting as a separate gated workstream.
5. Add device/account validation before claiming install/sign correctness.

---

## Appendix A — previous audit (`2664dad`)

The historical audit is preserved below for provenance. Its commit/branch differ from the current revision; findings marked **RESOLVED** above were addressed by the remediation recorded in `docs/SECURITY_RELIABILITY_REMEDIATION.md` (branch `arena/03624e7c-odysseus`, base `882ef8e2ad958d9a41463e61b62608c885315732`), whose changed-path list matches the current tree.

> *(The body of the previous audit is retained in the repository's prior revision of this file; the current revision supersedes its status claims.)*
