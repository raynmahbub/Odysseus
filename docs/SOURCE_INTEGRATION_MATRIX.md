# Source integration matrix

**Audit date:** 2026-10-31 (UTC) · **Revised:** 2026-10-31 (counts and status model corrected — see `BATCH1_READINESS_REVIEW.md` §2)
**Basis:** current Odysseus tree at `c2040b0` (byte-identical to the audited `2a54e3b` outside `docs/`) + shallow clones of verified upstreams at pinned commits (see `UPSTREAM_SOURCE_REGISTER.md`).
**Purpose:** inventory **distinct capabilities** (not broad categories), de-duplicate shared ancestry, and assign a proposed classification per capability before any code changes.

## Classification legend

| Class | Meaning |
|---|---|
| **KEEP** | Already present in Odysseus; retain as-is. |
| **CHERRY-PICK** | Select individual files/commits from an upstream that apply cleanly. |
| **COPY** | Copy a whole module/subtree, preserving license notices. |
| **ADAPT** | Port upstream code, changing identifiers/APIs/architecture to fit Odysseus. |
| **DEPENDENCY** | Adopt as a package/submodule dependency rather than vendoring source. |
| **INVESTIGATE** | Requires further verification (feasibility, license, platform) before a decision. |
| **BLOCKED** | Not feasible now (platform/entitlement/security/legal gate). |
| **EXCLUDE** | Not adopted (closed source, irrelevant, or rejected by owner). |

## Verification legend (per capability)

`SOURCE_VERIFIED · LICENSE_REVIEWED · IMPLEMENTED · BUILD_VERIFIED · AUTOMATED_TESTED · SIMULATOR_TESTED · PHYSICAL_DEVICE_TESTED · DOCUMENTED` — each is set only when evidence exists. Most upstream candidate features are currently `SOURCE_VERIFIED` only (code inspected); no new capability has been built yet.

## Status model — "implemented" is not one fact

Earlier revisions of this file wrote `IMPLEMENTED` for every existing capability. That single word conflated *code exists*, *code is new*, and *behaviour was tested*. Use these instead, and never claim more than the evidence:

| Status | Meaning | Evidence |
|---|---|---|
| `CODE_PRESENT` | In the baseline tree and reachable from the app | file path |
| `NEW_IN_BRANCH` | Added on the current branch | diff against `master` |
| `UNIT_TESTED` | An automated test exercises that behaviour | named test case |
| `BUILD_VERIFIED` | CI compiled and packaged it at a named commit | CI run id |
| `SIMULATOR_TESTED` / `PHYSICAL_DEVICE_TESTED` | Exercised at runtime | run log / device note |
| `NOT_RUN` | No evidence | — |

State of the tree at `c2040b0`: **0** capabilities are `NEW_IN_BRANCH`; **0** are `PHYSICAL_DEVICE_TESTED`; **1** existing capability is `UNIT_TESTED` in full (OD-CERT-01) and **3** more have partial automated coverage (OD-SIG-01, OD-APP-01, OD-LIB-01).

### Automated test coverage actually present (16 XCTest cases, 6 files)

| Test file | Cases | Capability covered |
|---|---|---|
| `OdysseusTests/ODZsignOutcomeTests.swift` | 5 | OD-SIG-01 — outcome validation only, not signing |
| `OdysseusTests/ODOCSPCoreTests.swift` | 2 | OD-CERT-01 — parser binding |
| `OdysseusTests/ODOCSPFreshnessTests.swift` | 2 | OD-CERT-01 — freshness window |
| `OdysseusTests/ODOCSPResponderAuthorizationTests.swift` | 3 | OD-CERT-01 — responder authorization |
| `OdysseusTests/StorageConcurrencyTests.swift` | 3 | persistence + OD-LIB-01 |
| `OdysseusTests/ODAppleIDMaterialCleanupTests.swift` | 1 | OD-APP-01 — temp-material cleanup only |

Everything else below is **code-present and untested**.

---

## Part 1 — Existing Odysseus capabilities (proposed KEEP)

These exist in the baseline tree at `c2040b0`. They are listed so the matrix is complete and so regressions are visible. All are `CODE_PRESENT`; the Status column records only the automated-test evidence above, and `BASELINE_AUDIT.md` §6 records the build evidence. None is device-verified.

| ID | Capability | Source / path | License | Duplicates | Class | Status |
|---|---|---|---|---|---|---|
| OD-DISC-01 | Discover storefront: featured carousel, New & Updated, Recently Added, per-source row, categories, search | `Views/Odysseus/Discover/*`, `ODCatalog*` | GPL-3.0 (Feather) | Ksign `AppstoreView`; FlekDeck installer | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-DISC-02 | Duplicate grouping ("available from N sources") + pick source | `ODCatalog.build` | GPL-3.0 | — | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-SRC-01 | AltStore/ESign sources: add by URL, QR, import/export, auto-refresh | `Views/Sources/*`, `Storage+Sources`, `DefaultSourceInstaller` | GPL-3.0 + MIT(AltSourceKit) | Ksign/RyukSign sources | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-LIB-01 | Library: Signed / Downloaded / Imported, expiry pills | `Views/Odysseus/Library/ODLibraryView.swift` | GPL-3.0 | RyukSign Library | KEEP | `CODE_PRESENT`; `UNIT_TESTED` (concurrency only) |
| OD-SIG-01 | Certificate signing via Zsign (`.p12`+`.mobileprovision`) | `ZsignHandler`, `SigningHandler`, `ODSignPipeline` | GPL-3.0 + MIT(zsign) | Ksign/RyukSign signing | KEEP | `CODE_PRESENT`; `UNIT_TESTED` (outcome validation only) |
| OD-SIG-02 | Bundle-ID prefix/suffix, entitlements, app name/version, appearance, min-iOS, file-sharing, URL-scheme removal | `SigningHandler._modifyDict`, `Options` | GPL-3.0 | Ksign/RyukSign signing options | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-SIG-03 | PPQ protection (append identifier, dynamic protection flag) | `Options.ppq*` | GPL-3.0 | — | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-SIG-04 | Tweak injection: `.dylib`/`.deb`/`.framework`/`.bundle`, ElleKit/CydiaSubstrate, extension injection | `TweakHandler` | GPL-3.0 + ElleKit(BSD-3) | Ksign/RyukSign tweaks | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-SIG-05 | Liquid Glass (SDK 26) + arm64e Mach-O fixups | `SigningHandler` + `Utilities/MachO/MachOUtils.m` | Apache-2.0 (LiveContainer) | LiveContainer patching | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-APP-01 | Apple ID signing (SideSign): login/2FA, anisette, cert/device/AppID/profile, p12 export | `Backend/AppleID/*`, `SideSign/` | AGPL-3.0 | SideStore | KEEP | `CODE_PRESENT`; `UNIT_TESTED` (temp-material cleanup only) |
| OD-CERT-01 | OCSP revocation checks + freshness + responder authorization | `Backend/Certificates/ODOCSP*` | GPL-3.0 | — | KEEP | `CODE_PRESENT`; `UNIT_TESTED` (OCSP parser, freshness, responder authz) |
| OD-CERT-02 | Certificate library, expiry reminders, revoked policy (warn/block/allow) | `ODCertificateStatusStore`, `ODPrefs` | GPL-3.0 | — | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-INS-01 | Semi-local install (local HTTP server + external plist server + webview redirect) | `ServerInstaller*`, `InstallPreviewView` | GPL-3.0 + Vapor | Ksign/RyukSign servers | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-INS-02 | Fully-local install with user-owned TLS identity | `ODLocalServerTLS`, `ServerView` | GPL-3.0 | — | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-INS-03 | Pairing-file + LocalDevVPN install via IDevice | `FR.movePairing`, `HeartbeatManager`, IDeviceKitten | MIT(idevice) | FlekPair/RyukSign | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-DIA-01 | Diagnostics + log export | `ODDiagnosticsView`, `Logger++` | GPL-3.0 | Ksign/RyukSign logs | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-UI-01 | Themes/tint, appearance, iOS 18/26 tab bar, iPad sidebar | `ODTheme`, `ODRootView` | GPL-3.0 | FlekDeck personalization | KEEP | `CODE_PRESENT`; `NOT_RUN` |
| OD-URL-01 | `odysseus://` URL schemes (cert select/import/export, source, install) | `FeatherApp._handleURL` | GPL-3.0 | Ksign `ksign://` | KEEP | `CODE_PRESENT`; `NOT_RUN` |

---

## Part 2 — Candidate capabilities from verified upstreams

### Group A — Feather upstream (`claration/Feather`, GPL-3.0)

| ID | Capability | Upstream files | Odysseus already? | Duplicates | Class | Notes |
|---|---|---|---|---|---|---|
| F-UPD-01 | App update checker: compare installed vs source versions, flag updates | `Backend/Observable/UpdateManager.swift`, `Backend/Storage/Storage+SourceMetadata.swift` | No | R-UPD-01 | **ADAPT** | Reclassified from CHERRY-PICK: depends on an `AppSourceMetadata` entity **and** on a provenance write path that Odysseus lacks (`AppInfoPresentable.source` is never assigned). Cannot be cherry-picked; see `BATCH1_READINESS_REVIEW.md` §3. |
| F-TAB-01 | Custom configurable tab bar (Extended/Varied tabbar) | `Views/TabView/*` | No (replaced by OD tab bar) | R-TABBAR-01 | INVESTIGATE | Odysseus has its own iOS 18/26 tab bar; upstream tab bar may conflict. Prefer RyukSign's preference-driven approach. |

### Group B — Ksign (`Nyasami/Ksign`, GPL-3.0)

| ID | Capability | Upstream files | Odysseus already? | Duplicates | Class | Notes |
|---|---|---|---|---|---|---|
| K-WEBDL-01 | Download IPA from arbitrary web pages (WebView + download manager) | `Views/Downloader/*`, `IPADownloadManager.swift` | No (only source-driven + URL scheme) | — | ADAPT | Needs WKWebView + download interception; security-sensitive (arbitrary URLs). |
| K-FILES-01 | On-device file manager: browse, hex edit, plist edit, text edit, QuickLook, images | `Views/Files/*` | No | — | COPY/ADAPT | Large UI module. Reuse `HexEditorView`, `PlistEditorView`, `QuickLookPreview`. |
| K-FILES-02 | Certificate inspection/service inside Files | `Views/Files/Utils/CertificateService.swift` | Partial (`CertificateReader`) | OD-CERT-01 | ADAPT | Merge with existing `CertificateReader`. |
| K-EXTRACT-01 | Extract/archive manager | `Backend/Observable/ExtractManager.swift` | Partial (`ArchiveHandler`) | R-ARCHIVE-01 | ADAPT | Overlaps Odysseus archive/compression. |
| K-DYLIB-01 | Dedicated frameworks/dylibs library browser | `Views/Library/Frameworks&Dylibs/*` | No | — | CHERRY-PICK | Small view; depends on tweak storage layout. |
| K-BULKINST-01 | Bulk install preview + progress | `Views/Library/Install/BulkInstall{Preview,Progress}View.swift` | No | R-BATCH-01 | CHERRY-PICK | UI-only; pair with a batch runner. |
| K-BULKSIGN-01 | Bulk signing view | `Views/Signing/BulkSigningView.swift` | No | R-BATCH-01 | CHERRY-PICK/ADAPT | UI; needs a batch engine (see R-BATCH-01). |
| K-LOGS-01 | Logs manager/model/view | `Backend/Observable/LogsManager.swift`, `LogsModel.swift`, `Views/Settings/Logs/LogsView.swift` | Partial (`ODDiagnosticsView`) | R-LOG-01 | ADAPT | Prefer one logs implementation (Odysseus diagnostics vs Ksign logs vs RyukSign logs). |
| K-APPSTORE-01 | Appstore storefront tab | `Views/Appstore/AppstoreView.swift` | No (Discover exists) | OD-DISC-01, FlekDeck installer | EXCLUDE/INVESTIGATE | Odysseus Discover already covers storefront; Ksign's is ESign-style. Likely EXCLUDE. |
| K-RSD-01 | RSD (Remote Services Daemon / developer disk image) support | release notes v1.6 | No | — | INVESTIGATE | Platform-specific; verify what "RSD support" means in Ksign source. |
| K-UTTYPE-01 | UTType extensions for cert/ipa/plist/tweak | `Extensions/UTType/*` | Partial (`UTType++`) | — | CHERRY-PICK | Small, low-risk. |
| K-SHORTCUT-01 | FileManager shortcuts/helpers | `Extensions/FileManager/*` | Partial | — | CHERRY-PICK | Small. |
| K-ACCENT-01 | Accent color manager | `Extensions/Color/AccentColorManager.swift` | No (ODTheme tint) | OD-UI-01 | INVESTIGATE | Overlaps ODTheme. |

### Group C — RyukSign (`faroukbmiled/RyukSign`, GPL-3.0)

| ID | Capability | Upstream files | Odysseus already? | Duplicates | Class | Notes |
|---|---|---|---|---|---|---|
| R-UPD-01 | App update checker with per-app ignore/skip + settings | `Backend/Observable/AppUpdateChecker.swift`, `SkippedUpdatesManager.swift`, `Views/Settings/Updates/IgnoredUpdatesView.swift` | No | F-UPD-01 | **ADAPT** | Reclassified from CHERRY-PICK/ADAPT. Preferred source for the **skip list** only. Its matcher needs an `originalIdentifier` attribute Odysseus lacks, matches on app **name** (false positives), and reads `FetchedResults` off the main thread. `Views/Settings/Updates/UpdatesSettingsView.swift` is *self-update* UI, not app updates — it does not belong to this row. See `BATCH1_READINESS_REVIEW.md` §3.4. |
| R-UPD-02 | Self-update | `SelfUpdateManager.swift`, `Views/Updates/SelfUpdateSheet.swift` | No | — | ADAPT | Odysseus has a nightly release workflow; in-app self-update is a product decision. |
| R-TWEAKMGR-01 | Tweak Manager: import/organize/inject; multi-file tweaks; per-file config; file-info/dependency inspector; ElleKit/Substrate detection | `Backend/Observable/TweakManager.swift`, `TweakModels.swift`, `Utilities/Handlers/Tweak{Analyzer,Extractor}.swift`, `Views/Tweaks/*` | Partial (per-sign injection only) | K-DYLIB-01 | COPY/ADAPT | Biggest distinct feature. Turns tweak injection from per-sign into a managed library. |
| R-LIVEACT-01 | Live Activities + Dynamic Island download progress | `DownloadManager+LiveActivity.swift`, `DownloadProgressAttributes.swift`, `Views/Download/DownloadOverlay*` | No | — | ADAPT | Requires Widget Extension target + App Intents. |
| R-LIVEACT-02 | App Intents download control | `Backend/AppIntents/DownloadControlIntent.swift` | No | R-LIVEACT-01 | ADAPT | Pairs with Live Activities. |
| R-DOWNLOAD-01 | Enhanced download manager (speed tracker, merged downloads, phases) | `DownloadManager+Delegates.swift`, `DownloadSpeedTracker.swift`, `Views/Download/MergedDownloadsView.swift` | Partial (`DownloadManager`) | — | ADAPT | Extend existing `DownloadManager`. |
| R-WEB-01 | HTTP file-transfer server (drag-drop browser) | `Backend/Server/WebManagerServer+HTTP.swift`, `WebManagerServer.swift`, `Views/Settings/Web Manager/WebManagerView.swift` | No | OD-INS-01 | ADAPT | Reuse Vapor server infrastructure. |
| R-WEB-02 | WebDAV file-transfer server | `WebManagerServer+WebDAV.swift` | No | R-WEB-01 | ADAPT | Needs WebDAV routing on the Vapor server. |
| R-WEB-03 | Password protection for the transfer server | (in WebManagerServer) | No | — | ADAPT | Auth on the local server. |
| R-BATCH-01 | Batch/bulk signing engine + install queue + cleanup | `BatchJobRunner.swift`, `InstallQueue.swift`, `InstallCleanup.swift`, `Views/Library/Batch/*` | No | K-BULKSIGN-01, K-BULKINST-01 | COPY/ADAPT | Core engine; unlocks Ksign bulk UI. |
| R-BACKUP-01 | Encrypted backup of signed apps/certs | `BackupManager.swift`, `BackupCrypto.swift`, `Views/Settings/Backup/*` | No | SS-BACKUP-01 | ADAPT | Overlaps SideStore SideBackup; decide one. |
| R-AUTOSIGN-01 | Auto-sign manager (sign on import) | `AutoSignManager.swift`, `AppInstaller.swift` | No | — | ADAPT | Product behavior; verify against Odysseus Get flow. |
| R-ENT-01 | Entitlements manager/editor | `EntitlementsManager.swift`, `Utilities/MachOEntitlements.swift`, `Views/Signing/Entitlements/*` | Partial (entitlements file option) | — | ADAPT | Extend `Options.appEntitlementsFile`. |
| R-PLIST-01 | Info.plist editor (plan/diff/raw) | `Utilities/{InfoPlistPlan,PlistDiff}.swift`, `Views/Signing/InfoPlist/*`, `Views/Signing/Shared/Plist*` | Partial (`SigningHandler` plist edits) | — | ADAPT | Turns hard-coded modifications into an editor. |
| R-CERTAUTO-01 | Certificate auto-importer | `CertificateAutoImporter.swift` | No | — | CHERRY-PICK | Small. |
| R-IDVAULT-01 | Identity vault (store/manage signing identities) | `Utilities/IdentityVault.swift` | Partial (`ODKeychain`) | — | ADAPT | Overlaps OD Keychain. |
| R-LOG-01 | File logging + stdout capture + log history + signing log | `FileLogger.swift`, `StdoutCapture.swift`, `LogPresentation.swift`, `LogsHistoryView.swift`, `SigningLog.swift` | Partial (`ODDiagnosticsView`) | K-LOGS-01 | ADAPT | Consolidate logging. |
| R-STORAGE-01 | Storage manager + storage detail view | `StorageManager.swift`, `Views/Settings/Storage/*` | No | — | CHERRY-PICK | Small. |
| R-TABBAR-01 | Configurable tab bar preferences | `TabBarPreferences.swift`, `Views/Settings/TabBarSettingsView.swift` | No | F-TAB-01 | ADAPT | Preference-driven; fits Odysseus tabs. |
| R-MACHO-01 | Mach-O reader + entitlements extraction | `MachOReader.swift`, `MachOEntitlements.swift` | Partial (`MachOUtils`) | — | ADAPT | Reuse for entitlements editor. |
| R-ARCHIVE-01 | Archive engine / app archiver | `ArchiveEngine.swift`, `AppArchiver.swift` | Partial (`ArchiveHandler`) | K-EXTRACT-01 | ADAPT | Consolidate archiving. |
| R-APPEXT-01 | App-extension enumerator | `AppExtensionEnumerator.swift` | Partial (`TweakHandler._discoverAppExtensions`) | — | CHERRY-PICK | Small. |
| R-LINKS-01 | Link/Telegram tag parsers | `LinkTagParser.swift`, `TelegramLinkParser.swift` | No | — | CHERRY-PICK | Small; only if source formats need it. |
| R-PREMIUM-01 | Curated/premium repository filtering | `PremiumManager.swift`, `PremiumFilterPreferences.swift`, `Views/Sources/PremiumSettingsView.swift` | No | — | INVESTIGATE | Business/curration feature; verify licensing/revenue model. |
| R-NAV-01 | App navigation manager | `AppNavigationManager.swift` | No | — | CHERRY-PICK | Small. |

### Group D — LiveContainer / FlekDeck (AGPL-3.0) — app container workstream

| ID | Capability | Upstream files | Odysseus already? | Duplicates | Class | Notes |
|---|---|---|---|---|---|---|
| LC-CORE-01 | Run iOS apps without installing (live container) | `LiveContainer/` (main executable) | No (only Mach-O fixup) | FlekDeck core | **BLOCKED** | Requires major architecture + entitlements; security workstream. |
| LC-PATCH-01 | Guest Mach-O patching (`__PAGEZERO`, `MH_DYLIB`, `_NSGetExecutablePath`, `NSBundle.mainBundle`) | `LiveContainer/` | Partial (SDK26/arm64e fixups only) | — | **BLOCKED** | Subset of LC-CORE-01. |
| LC-DLOPEN-01 | `dlopen` guest + entry-point jump + tweak loading | `LiveContainer/`, `TweakLoader/` | No | — | **BLOCKED** | Subset of LC-CORE-01. |
| LC-KEYCHAIN-01 | 128 keychain access groups for multi-account | `entitlements.xml` | No | — | **BLOCKED** | Needs entitlement + keychain rework. |
| LC-MULTI-01 | Multitasking support (virtual windows / PiP) | `MultitaskSupport/` | No | FlekDeck multitasking | **BLOCKED** | Depends on LC-CORE-01. |
| LC-EXT-01 | LaunchAppExtension / ShareExtension | `LaunchAppExtension/`, `ShareExtension/` | No | — | **BLOCKED** | Depends on LC-CORE-01. |
| LC-SIDESTORE-01 | SideStore refresh integration inside container | `SideStoreSupport/` | No | SS-REFRESH-01 | **BLOCKED** | Depends on LC-CORE-01 + SideStore. |
| LC-HOME-01 | Home-screen launcher UI (FlekDeck) | `LiveContainerSwiftUI/FlekDeck/*`, `Dragula` | No | LC-CORE-01 | **BLOCKED** | Subset of FlekDeck; depends on LC-CORE-01. |
| LC-SEARCH-01 | Universal search across apps + repos (FlekDeck) | `LiveContainerSwiftUI/` | No | OD-DISC-01 | **BLOCKED** | Depends on LC-CORE-01. |
| LC-PARALLEL-01 | Parallel downloads with per-icon progress (FlekDeck) | `LiveContainerSwiftUI/` | No | R-DOWNLOAD-01 | **BLOCKED** | Depends on LC-CORE-01. |
| LC-PERSONALIZE-01 | Wallpapers/glass/bar shapes/haptics (FlekDeck) | `LiveContainerSwiftUI/FlekStore/*` | No | OD-UI-01 | **BLOCKED** | Depends on LC-CORE-01. |
| LC-GAME-01 | Automatic game detection (FlekDeck) | `LiveContainerSwiftUI/` | No | — | **BLOCKED** | Depends on LC-CORE-01. |
| LC-PAIRING-01 | On-device pairing-file helpers (FlekDeck `IdevicePairing`) | `IdevicePairing/` | Partial (pairing import) | OD-INS-03, FlekPair | INVESTIGATE | May be reusable without full container. |
| LC-TWEAKLDR-01 | Tweak loader injected into every guest app | `TweakLoader/` | No | OD-SIG-04 | **BLOCKED** | Depends on LC-CORE-01. |

### Group E — SideStore (AGPL-3.0)

| ID | Capability | Upstream files | Odysseus already? | Duplicates | Class | Notes |
|---|---|---|---|---|---|---|
| SS-REFRESH-01 | Untethered app refresh via VPN (EM Proxy/LocalDevVPN/Jitterbug) | `SideStore/`, `Dependencies/` | No (SideSign only) | LC-SIDESTORE-01 | **INVESTIGATE** | Large; Rust deps; different install transport than Odysseus's server/pairing. |
| SS-BACKUP-01 | SideBackup app/extension | `SideBackup/` | No | R-BACKUP-01 | INVESTIGATE | Overlaps RyukSign backup; pick one. |
| SS-ALTSTORE-01 | AltStore fork base (Roxas, marketplace) | `AltStore/`, `Shared/` | Partial (AltSourceKit) | — | INVESTIGATE | Mostly inherited; not a distinct user feature. |

### Group F — Unverified / not adoptable

| ID | Capability | Source | Class | Reason |
|---|---|---|---|---|
| UV-FP-01 | FeatherPlus (MobileGestalt, Settings.bundle) | `TomerGamerTV/FeatherPlus` @ `9af4713` | **EXCLUDE** | Verified Feather fork; **no distinct capability** — Odysseus already has `MobileGestalt.swift`. Removes two upstream features (`mergeEntitlements`, `LCGetMachOEntitlements`). |
| UV-ZEUS-01 | Zeus: IPSW firmware browser + curated IPA library | `getzeus.app` (closed-source; no source repo) | **CONCEPT-ONLY** | Closed-source app. IPA Library ≈ Odysseus sources/Discover; **IPSW browser is a novel concept** — reimplement only if approved. |
| UV-FS-01 | FlareStore: signing log/presets, entitlements/plist editors, backup, Update All, Live Activity downloads, Apple TV/Watch/Vision, self-update | `flarestore.app` (closed-source; no source repo) | **CONCEPT-ONLY** | Closed-source platform; rich concept reference, no source reuse possible. |
| UV-FPAIR-01 | FlekPair (desktop pairing generator) | `flekstore/FlekPair` | **EXCLUDE** | Source not published; desktop Tauri app; not applicable on-device. |

---

## Part 3 — Consolidation decisions (de-duplication)

1. **Update checking:** `F-UPD-01` and `R-UPD-01` are duplicates. Adopt **R-UPD-01** (more complete); treat Feather's as the fallback reference.
2. **Bulk/batch signing:** `K-BULKSIGN-01`, `K-BULKINST-01`, `R-BATCH-01` overlap. Adopt **R-BATCH-01** engine; optionally cherry-pick Ksign's bulk UI.
3. **Logs/diagnostics:** `K-LOGS-01`, `R-LOG-01`, `OD-DIA-01` overlap. Consolidate into one logging subsystem; keep `ODDiagnosticsView` as the UI shell.
4. **Archive/extraction:** `K-EXTRACT-01`, `R-ARCHIVE-01`, `OD` `ArchiveHandler` overlap. Consolidate.
5. **Backup:** `R-BACKUP-01` and `SS-BACKUP-01` overlap. Choose one (recommend RyukSign's, adapted, unless SideStore refresh is adopted).
6. **Tweak management:** `R-TWEAKMGR-01` subsumes `K-DYLIB-01`. Adopt RyukSign's manager.
7. **App container:** all `LC-*` depend on `LC-CORE-01`, which is **BLOCKED**. Do not start until the feasibility gate is approved.
8. **SideStore:** `SS-REFRESH-01` is orthogonal to Odysseus's install paths but is a large, distinct transport. Keep as a separate workstream.

## Part 4 — Summary

### Counting rules

A row is one **distinct capability**, counted exactly once. Duplicates are noted in the "Duplicates" column but are not extra rows. Part 2 groups are `###` subsections under one `##` part; the earlier summary under-counted because the group rows were missed.

| Part | Group | Rows |
|---|---|---|
| 1 | Existing Odysseus (KEEP) | **18** |
| 2A | Feather | 2 |
| 2B | Ksign | 13 |
| 2C | RyukSign | 25 |
| 2D | LiveContainer / FlekDeck | 14 |
| 2E | SideStore | 3 |
| 2F | Unverifiable / not adoptable | 4 |
| | **Part 2 total** | **61** |
| | **Total inventoried** | **79** |

### Classification totals (Part 2)

| Class | Rows |
|---|---|
| Adoptable (`ADAPT` 22, `CHERRY-PICK` 9, `COPY/ADAPT` 3, `CHERRY-PICK/ADAPT` 1) | **35** |
| `INVESTIGATE` | 8 |
| `EXCLUDE/INVESTIGATE` | 1 |
| `BLOCKED` (all LiveContainer/FlekDeck dependents) | 13 |
| `EXCLUDE` | 2 |
| `CONCEPT-ONLY` | 2 |
| **Total** | **61** |

### Status totals (whole matrix)

| Status | Rows |
|---|---|
| `NEW_IN_BRANCH` | **0** |
| Existing capabilities with full automated coverage | 1 (OD-CERT-01) |
| Existing capabilities with partial automated coverage | 3 (OD-SIG-01, OD-APP-01, OD-LIB-01) |
| Existing capabilities with no automated test | 14 |
| Device-verified capabilities | **0** |

- Distinct capabilities inventoried: **79** (Part 1: 18 existing; Part 2: 61 candidates/blocked/excluded).
- After de-duplication (Part 3), **candidate adoptable feature groups**: update checking, IPSW firmware browser (from closed-source Zeus; reimplement from scratch), tweak manager, bulk signing, web/WebDAV transfer, Live Activities, file manager, storage manager, tab-bar config, entitlements/plist editors, certificate auto-import, link parsers, UTType/shortcut helpers.
- **BLOCKED:** entire LiveContainer/FlekDeck app-container workstream (`LC-CORE-01` and dependents).
- **EXCLUDE:** FlekPair.
- **CONCEPT-ONLY (closed-source; no source reuse possible):** Zeus (IPSW firmware browser), FlareStore (signing log/presets, entitlements/plist editors, backup, Update All, Live Activity downloads, Apple TV/Watch/Vision, self-update).
- No candidate has been implemented in this audit; all new capabilities are `SOURCE_VERIFIED` (code inspected) only. `IMPLEMENTED` is not used for anything in this tree — see the status model above.
