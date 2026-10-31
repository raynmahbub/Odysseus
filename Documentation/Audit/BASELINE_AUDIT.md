# Odysseus baseline audit

**Audit date:** 2026-10-31 (UTC)
**Repository:** `https://github.com/raynmahbub/Odysseus.git`
**Branch inspected:** `arena/36737ef3-odysseus`
**HEAD:** `6ee21d6800757bbd8b3c76e78b9b0b750800563d` — *docs(audit): answer the Batch 1 readiness review and rescope it*
**`master`:** `6ee21d6…` (identical to HEAD)
**Working tree:** clean at the start of the audit (`git status --porcelain` empty)
**Mode:** audit and documentation only — **no production code was modified**

This document establishes *what exists and what has been proven*, so the later audits can be read against a fixed baseline. It replaces the baseline section of the earlier `docs/` package (see §9 for the relationship between the two trees).

---

## 1. Method

| Activity | Performed | Evidence |
|---|---|---|
| Read the full Swift/ObjC tree (113 `.swift`, 5 `.m`/`.h`, 16,861 lines under `Feather/`) | yes | file inventory, §4 |
| Read the project file, xcconfigs, entitlements, Info.plist, Makefile, CI workflow | yes | §2, §6 |
| Traced the signing, install, import, source-refresh and update paths end to end | yes | `ODYSSEUS_ARCHITECTURE_AUDIT.md` §4–§7 |
| Inspected CI results from GitHub Actions | yes | §7 |
| Ran `xcodebuild`, `swiftc`, XCTest, `codesign` | **no — impossible here** | §7.3 |
| Ran the app on a simulator or device | **no** | §7.3 |
| Inspected upstream sources at pinned commits | yes | `UPSTREAM_SOURCE_REGISTER.md` |

Everything below is stated as either **verified** (with a path) or **not verified** (with the reason). No claim in this audit is based on a README, a product page, or a prior document.

---

## 2. Repository and build facts

| Fact | Value | How verified |
|---|---|---|
| Branches present | `arena/36737ef3-odysseus` = `master` = HEAD | `git rev-parse`, `git ls-remote` |
| History | single squashed commit; `2a54e3b` (prior audit revision) is unreachable locally; tag `nightly` → `2a54e3b` exists on the remote | `git log`, `git cat-file`, `git ls-remote --tags` |
| App target | one iOS application target, internal name `Feather`, product `Odysseus` | `Feather.xcodeproj/project.pbxproj` |
| Scheme | `Feather` (shared) | `Feather.xcodeproj/xcshareddata` |
| Project format | `objectVersion = 77`; sources are `PBXFileSystemSynchronizedRootGroup` folders (`Feather`, `OdysseusTests`) — **new files need no pbxproj edit** | `project.pbxproj` §58–73 |
| Deployment target | iOS **17.0** (tests also 17.0); `TARGETED_DEVICE_FAMILY = "1,2"` | `project.pbxproj` |
| Swift | `SWIFT_VERSION = 5.0` (app); SideSign package uses Swift tools 6.0 / language mode v6 | `project.pbxproj`, `SideSign/Package.swift` |
| Bundle ID | `com.mirazbakis.Odysseus` (+ `$(FEATHER_DISAMBIGUATOR)`) | `project.pbxproj`, `Feather.xcconfig` |
| Signing | `CODE_SIGN_STYLE = Manual`; Makefile builds with `CODE_SIGNING_ALLOWED=NO` and ad-hoc signs the payload | `Makefile` |
| Entitlements | **only** `get-task-allow` | `Feather/Supporting Files/Feather.entitlements` |
| Background modes | `audio` (used to keep downloads alive) | `Feather/Resources/Info.plist` |
| File sharing | `UIFileSharingEnabled = true` | `Info.plist` line 106 |
| URL scheme | `odysseus` with six handlers | `Info.plist`, `FeatherApp.swift` §81–175 |
| ATS | HTTP exceptions for `certs.apple.com`, `crl.apple.com`, `ocsp.apple.com` only | `Info.plist` §71–99 |
| Test target | `com.mirazbakis.OdysseusTests`, hosted in the app; **16 XCTest cases in 6 files** | `OdysseusTests/` |
| Local packages | `AltSourceKit`, `NimbleKit`, `Zsign` (submodule), `IDeviceKitten` (submodule), `SideSign` (vendored) | repo tree |
| Remote packages | `vapor`, `Nuke`, `Zip` (marmelroy), `SWCompression`, `LicensePlist`, `BitByteData` | `project.pbxproj` §672–721 |
| Root `Package.resolved` | **absent** — remote package versions resolve at build time | repo tree |
| Submodules populated | **no** (`Zsign`, `IDeviceKitten` working trees are empty) | `git submodule status` |

### 2.1 Size and shape

| Area | Files | Lines |
|---|---|---|
| `Feather/` (app) | 113 Swift + 5 ObjC/C | 16,861 Swift |
| `SideSign/` (vendored, AGPL-3.0) | package | 8,609 Swift |
| `OdysseusTests/` | 6 | 357 |
| `AltSourceKit/`, `NimbleKit/` | local packages | included above only where referenced |

Largest back-end modules: `ODAppleIDManager.swift`, `ODSignPipeline.swift`, `ODOCSPChecker.swift`, `SigningHandler.swift`, `TweakHandler.swift`, `Storage.swift`. There is **no framework boundary** between "Feather" code and "Odysseus" code; they compile as one module and share internal types.

---

## 3. State of the code at this revision

The tree at `6ee21d6` differs from the previously audited app revision (`2a54e3b`) **only in `docs/`**. Verified by comparing the GitHub tree object for every top-level path:

- `Feather` tree SHA at `2a54e3b`: `c996af8e9f653ea3e668558371bd0e4603516f22`
- `git rev-parse HEAD:Feather`: `c996af8e9f653ea3e668558371bd0e4603516f22`
- 27/27 top-level entries identical except `docs/`.

Therefore every code-level finding in the earlier package still applies, and this audit re-verified the ones it depends on directly against the files (paths and line numbers cited throughout).

---

## 4. Module map (verified)

| Concern | Key paths | State |
|---|---|---|
| App entry, lifecycle, URL handling | `Feather/FeatherApp.swift`, `AppDelegate` | present |
| Root navigation | `Views/Odysseus/ODRootView.swift` | present; two layout branches (iOS 18 TabView / legacy) with duplicated tab lists |
| Storefront / catalog | `Views/Odysseus/Discover/{ODDiscoverView,ODCatalog,ODCatalogStore,ODAppPageView,ODGetButton}.swift` | present; catalog is in-memory only |
| Sources | `Views/Sources/*`, `Backend/Storage/Storage+Sources.swift`, `Backend/Services/DefaultSourceInstaller.swift`, `AltSourceKit` | present |
| Library | `Views/Odysseus/Library/{ODLibraryView,ODCertificateCards}.swift`, `Views/Library/*` | present |
| Signing pipeline | `Backend/Odysseus/ODSignPipeline.swift`, `Utilities/FR.swift`, `Utilities/Handlers/{SigningHandler,ZsignHandler,TweakHandler,AppFileHandler,ArchiveHandler,CertificateFileHandler}.swift` | present; single seam |
| Apple ID signing | `Backend/AppleID/{ODAppleIDManager,ODKeychain,ODAppleIDSignedApps}.swift`, `Views/Odysseus/Settings/ODAppleIDView.swift`, `SideSign/` | present |
| Revocation | `Backend/Certificates/{ODOCSPChecker,ODOCSPCore,ODX509,ODDER,ODCertificateStatusStore}.swift` | present; strongest tested module |
| Installation | `Backend/Server/{ServerInstaller,ServerInstaller+TLS,ServerInstaller+Compute,ODLocalServerTLS}.swift`, `Views/Odysseus/Install/ODInstallSheet.swift` | present |
| Persistence | `Backend/Storage/Storage*.swift`, `Feather.xcdatamodeld` (single unversioned model) | present |
| Preferences | `Backend/Odysseus/ODPrefs.swift`, `Backend/Observable/OptionsManager.swift` | present |
| Diagnostics | `Views/Odysseus/Settings/ODDiagnosticsView.swift`, `Extensions/Logger++.swift` | present; OSLog-based export |
| Downloads | `Backend/Observable/DownloadManager.swift`, `Utilities/BackgroundTaskManager.swift`, `Utilities/BackgroundAudioManager.swift` | present |
| Work around the OS | `Utilities/MobileGestalt.swift`, `Utilities/MachO/MachOUtils.m` | present; private API + Apache-2.0 port |
| Tests | `OdysseusTests/*.swift` | 16 cases |

---

## 5. Feature surface at a glance

Full row-by-row detail is in `ODYSSEUS_FEATURE_MATRIX.md`. Summary:

- **Substantial and unique to Odysseus:** certificate revocation checking (OCSP), fully-local TLS install mode, pairing/IDevice install, Apple ID signing via SideSign, the Discover storefront with duplicate grouping, and the snapshot/queue discipline in persistence.
- **Present and Feather-derived:** signing (Zsign), tweak injection, archive import/export, source management, library, themes.
- **Absent:** app update checking, bulk signing, web/WebDAV transfer, file manager, Live Activities, backup, self-update, entitlements/plist editors beyond the existing options, offline source cache, install history, IPSW anything.
- **Not device-verified:** every install path, Apple ID portal interaction, live OCSP against Apple, and every signing result.

---

## 6. CI and build evidence

Workflow `.github/workflows/build.yml` runs on `macos-26` with Xcode `26.4`:
checkout with `submodules: recursive` → `xcodebuild test` (iPhone 17 simulator) → `make iphoneos` → `scripts/verify_ipa.sh` → upload IPA → publish.

| Run | Commit | Branch | Result |
|---|---|---|---|
| `41198043032` | `2a54e3b` | `master` | **success** — tests + IPA + verify |
| `41219757550` | `fe0f37e` | `arena/088597d5-odysseus` | **success** — same job |
| `41222160759` | `6ee21d6` branch tip | `arena/b50aa4f2-odysseus` | in progress at audit time |

Conclusion: **the baseline app code compiles, the 16 unit tests pass, and the produced IPA passes `scripts/verify_ipa.sh`, as of run `41198043032`.** That is build evidence, not device evidence.

### 6.1 What the CI does *not* prove

Signing a real app with a real certificate, installing on a device, every install transport, Apple ID portal behaviour, live OCSP interoperability, background download behaviour, and anything under `#if targetEnvironment(macCatalyst)`.

---

## 7. Local verification in this environment

### 7.1 Environment

Linux host, no Apple toolchain, no `xcodebuild`/`swiftc`/`xcrun`, no simulator, no device, empty submodules (`Zsign`, `IDeviceKitten`). Only static inspection plus GitHub API/CI reads were possible.

### 7.2 Commands that were run

```
git branch --show-current && git rev-parse HEAD
git status --porcelain
git submodule status
git ls-remote --tags origin
gh run list --limit 5
gh run view 41198043032 --json headSha,conclusion,jobs
find Feather -name '*.swift' | wc -l
```

### 7.3 Commands that must be run on macOS before any release

```
git submodule update --init --recursive
xcodebuild test -project Feather.xcodeproj -scheme Feather \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath build/tests CODE_SIGNING_ALLOWED=NO
make iphoneos && scripts/verify_ipa.sh packages/Odysseus.ipa
```

Expected results are recorded per task in `ODYSSEUS_TESTING_STRATEGY.md` §8.

---

## 8. Baseline integrity for the other audits

| Audit | Depends on this baseline for |
|---|---|
| `ODYSSEUS_FEATURE_MATRIX.md` | status of every existing feature |
| `ODYSSEUS_ARCHITECTURE_AUDIT.md` | module boundaries, data flow |
| `ODYSSEUS_BUG_AND_RELIABILITY_AUDIT.md` | line-level defect evidence |
| `ODYSSEUS_SECURITY_REVIEW.md` | entitlements, ATS, keychain, file handling |
| `ODYSSEUS_TESTING_STRATEGY.md` | what is already covered |
| `ODYSSEUS_IMPLEMENTATION_ROADMAP.md` | what must not regress |

---

## 9. Relationship to the earlier `docs/` package

The repository already contains a prior audit package in `docs/` (`BASELINE_AUDIT.md`, `ARCHITECTURE.md`, `INTEGRATION_PLAN.md`, `SOURCE_INTEGRATION_MATRIX.md`, `UPSTREAM_SOURCE_REGISTER.md`, `BATCH1_READINESS_REVIEW.md`, `SECURITY_RELIABILITY_REMEDIATION.md`), merged before this task.

This `Documentation/Audit/` tree is the **complete, current audit** requested for this task and is authoritative where the two disagree. The `docs/` files are left untouched (no deletions, no rewrites) as history. Where the earlier package contained an error that this audit corrects, the correction is recorded in place:

| Earlier claim | Correction | Where |
|---|---|---|
| `odysseus://export-certificate` is "guarded by Face ID" | It is guarded by an alert only; Face ID exists **only** on the Apple ID export path | `ODYSSEUS_SECURITY_REVIEW.md` S-01 |
| Feature counts 17/43/60 | 18/61/79 rows (already corrected in the prior package) | `ODYSSEUS_FEATURE_MATRIX.md` |
| "Implemented" for 17 capabilities | split into code-present / tested / device-verified | `ODYSSEUS_FEATURE_MATRIX.md` status model |
