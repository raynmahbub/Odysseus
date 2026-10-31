# Upstream source register

**Audit date:** 2026-10-31 (UTC)
**Basis:** GitHub API + `git ls-remote` + shallow clones (`--depth 1`) into `/tmp/upstream`, inspected directly. Each entry records what is confirmed by code/documentation vs inferred.
**Purpose:** fix the intended repository, branch, commit, license, and lineage for every project named in the integration brief *before* any code is copied.

Status legend: **VERIFIED** (repo located, inspected, identity/license confirmed) · **AMBIGUOUS** (a candidate exists but identity is not certain) · **UNVERIFIED** (no plausible repository located; must be clarified before use).

---

## 1. Register

| # | Project (as named) | Resolved repository | Default branch | HEAD commit (at audit) | License | Status |
|---|---|---|---|---|---|---|
| 1 | Feather | `claration/Feather` (formerly `khcrysalis/Feather`; `gh api repos/khcrysalis/Feather` redirects to `claration/feather`) | `main` | `7078b053c0af262809a48e4d3898d42b0d35fedf` | GPL-3.0 | **VERIFIED** |
| 2 | FeatherPlus | *none found* | — | — | — | **UNVERIFIED** |
| 3 | KSign | `Nyasami/Ksign` | `main` | `c14dedc0c9dadb669021cce83435b14f781b8412` | GPL-3.0 | **VERIFIED** (case-sensitive clone: `Nyasami/ksign.git`) |
| 4 | RyukSign | `faroukbmiled/RyukSign` | `main` | `844466cee6f212291913ba5216f8f19a9c016dea` | GPL-3.0 | **VERIFIED** |
| 5 | FlareStore | *no matching iOS source repo* (closest: `acetex/flarestore`, JavaScript, 1 star, pushed 2022, no license — not an iOS app) | — | — | — | **UNVERIFIED** |
| 6 | LiveContainer | `LiveContainer/LiveContainer` | `main` | `9108ae624ea001f7d7696d48407f890b48fa2653` | AGPL-3.0 | **VERIFIED** |
| 7 | SideStore | `SideStore/SideStore` | `develop` | `cd260851ae99bf1fc946b123db24e89c8cd21dc6` | AGPL-3.0 | **VERIFIED** |
| 8 | Zeus | *no plausible iOS signing repo* (closest: `czstore/zeus` — HTML, no license, "free and paid ios mods", pushed 2021) | — | — | — | **UNVERIFIED** |
| 9 | FlekStore / FlekDeck | `flekstore/FlekDeck` (org/user `flekstore`) | `main` | `6ba96e1181ffe6c21e70ecdf71ae7027256a5e8d` | AGPL-3.0 | **VERIFIED** |
| 9a | (FlekStore) LiveContainer-FS | `flekstore/LiveContainer-FS` | `main` | `9d4d5dd49346d73ce7d3221651ce76e6e3681cbb` | Apache-2.0 | **VERIFIED** (fork of LiveContainer + SideStore) |
| 9b | (FlekStore) FlekPair | `flekstore/FlekPair` | `main` | `d30d67e54dfd15fe5522c365df8d8e4d5247399a` | *none* (Apache-2.0 removed in last commit) | **VERIFIED repo / source NOT published** |

### Related / already-integrated sources (for lineage and license accounting)

| Repo | Role in Odysseus | License | Notes |
|---|---|---|---|
| `claration/zsign` (submodule `Zsign`, branch `package`) | on-device signing engine | MIT | pinned `6ffe703df73ef9069adacdbb19d571f11a69a801` |
| `claration/idevicekit` (submodule `IDeviceKitten`) | install over pairing file | MIT | pinned `837cf1e14d4875771dd5ee1b754a4c86215c5db3` |
| `SideStore/Catalyst` → vendored `SideSign/` | Apple ID signing (Dev portal APIs, code signing) | AGPL-3.0 | vendored; deps CodeSignKit, GSACryptoKit, AnisetteKit, libdeflate |
| `altstoreio/AltStore` → vendored `AltSourceKit/` | source/repository parsing | MIT (Copyright 2025 CLARATION) | vendored local package |
| `claration` `NimbleKit` | UI/JSON helpers | MIT (Copyright 2025 CLARATION) | vendored local package |
| `FrizzleM/FreeSign` | cited in README as a base | GPL-3.0 | `main`; 8 stars; UI/handler lineage |

---

## 2. Per-project detail

### 2.1 Feather — `claration/Feather` — GPL-3.0 — VERIFIED

- **Identity:** the canonical Feather. `gh api repos/khcrysalis/Feather` redirects to `claration/feather`. Description: "Free on-device iOS/iPadOS application manager/installer, using certificates part of the Apple Developer Program." 4,970 stars.
- **Tree shape** matches Odysseus's vendored `Feather/` almost exactly (`Feather/`, `AltSourceKit/`, `NimbleKit/`, `Zsign/`, `IDeviceKitten/`, `Feather.xcconfig`, `Makefile`, `app-repo.json`).
- **Lineage:** Odysseus's `Feather/` is a **modified snapshot** of upstream Feather (not a git fork — see BASELINE_AUDIT §4.11). File-set diff at the audited revisions:
  - Upstream-only: `Backend/Observable/UpdateManager.swift`, `Backend/Storage/Storage+SourceMetadata.swift`, `Views/Library/LibraryView.swift` + `LibraryCellView.swift`, `Views/Settings/SettingsView.swift`, `Views/Settings/App Icon/AppIconView.swift`, `Views/Settings/SettingsDonationCellView.swift`, `Views/TabView/*` (custom tab bar), and various icon assets.
  - Odysseus-only: the entire `Backend/AppleID/`, `Backend/Certificates/`, `Backend/Odysseus/`, `Backend/Server/ODLocalServerTLS.swift`, `Backend/Services/DefaultSourceInstaller.swift`, `Views/Odysseus/*`, `Resources/WWDR/*`, `Resources/DefaultSources.json`, `Utilities/MobileGestalt.swift`.
- **Conclusion:** Odysseus already contains Feather's signing/install/tweak machinery. Remaining Feather-derived opportunities: the **app update checker** (`UpdateManager` + `Storage+SourceMetadata`) and Feather's custom **tab bar**.

### 2.2 FeatherPlus — UNVERIFIED

- GitHub repository search for `FeatherPlus` returns **zero** repositories; `claration` org repo list contains no such project; `feathers-plus` (a FeathersJS/JS project) is unrelated.
- **Action required:** ask the user for the exact repository URL (or confirm it does not exist / is private). **Do not substitute** another project without approval.

### 2.3 KSign — `Nyasami/Ksign` — GPL-3.0 — VERIFIED

- **Identity:** "The 'cleaner' Esign app." 724 stars. README states it is built on **Feather** as the base, recreating ESign's UX, and is built to share certificates (for Khoindvn).
- **Lineage:** Feather derivative. Same submodules (`AltSourceKit`, `NimbleKit`, `Zsign`, `IDeviceKit`) and same `Feather.xcdatamodeld`. Entitlements identical to Feather (`get-task-allow` only).
- **Module map (distinct from Feather):**
  - `Backend/Observable/{ExtractManager,LogsManager,LogsModel}.swift`
  - `Views/Appstore/AppstoreView.swift` (a storefront)
  - `Views/Downloader/*` (`IPADownloadManager`, `WebViewContainer`/`WebViewCoordinator`, `WebViewSheet`, `DownloadItem`) — download IPA from arbitrary web pages
  - `Views/Files/*` (file browser: `HexEditorView`, `PlistEditorView`, `TextEditorView`, `QuickLookPreview`, `ImageRow`, `CertificateService`, `ExtractionService`, `FileItem`, `FilesViewModel`)
  - `Views/Library/Frameworks&Dylibs/*` (dedicated dylib library)
  - `Views/Library/Install/BulkInstall{Preview,Progress}View.swift` — bulk install
  - `Views/Signing/BulkSigningView.swift` — bulk signing
  - `Views/Settings/{AppFeaturesView,Logs/LogsView,AppIcon/AppIconView}.swift`
  - `Views/Settings/Installation/Server & SSL/Models/ServerPackModel.swift`
  - `Extensions/{Date+stripTime,URL+scheme,UTType+cert/ipa/plist/tweak,FileManager+shortcuts,Image+appIconStyle,Text+bg,Color/AccentColorManager}.swift`
- **URL scheme:** `ksign://` (single scheme).
- **Release notes (v1.6)** confirm: bulk installation, idevice install method, custom injection path + inject into App Extensions, `.bundle` tweak support, **RSD support**, Info.plist display-name fix, URL scheme fixes.

### 2.4 RyukSign — `faroukbmiled/RyukSign` — GPL-3.0 — VERIFIED

- **Identity:** "an on-device app signer and installer for iOS, derived from Feather." 110 stars. Explicitly states it is a fork of Feather and preserves GPL-3.0. Ships `DISTRIBUTION` (an App-Store-TOS license-conflict waiver).
- **Lineage:** Feather derivative. Same `Feather.xcdatamodeld`, same submodules.
- **Module map (distinct from Feather):**
  - Tweak Manager: `Backend/Observable/{TweakManager,TweakModels}.swift`, `Utilities/Handlers/{TweakAnalyzer,TweakExtractor}.swift`, `Views/Tweaks/*`
  - Live Activities / Dynamic Island: `Backend/Observable/{DownloadManager+LiveActivity,DownloadProgressAttributes}.swift`, `Backend/AppIntents/DownloadControlIntent.swift`, `Views/Download/DownloadOverlay*`
  - Enhanced downloads: `DownloadManager+Delegates.swift`, `DownloadSpeedTracker.swift`, `Views/Download/{MergedDownloadsView,DownloadItemCardView,...}`
  - File transfer server: `Backend/Server/WebManagerServer{+HTTP,+WebDAV}.swift`, `Backend/Observable/WebManager.swift`, `Views/Settings/Web Manager/WebManagerView.swift`
  - App update checker: `Backend/Observable/AppUpdateChecker.swift`, `SkippedUpdatesManager.swift`, `Views/Settings/Updates/*`, `Views/Updates/SelfUpdateSheet.swift`, `Backend/Observable/SelfUpdateManager.swift`
  - Batch signing: `Backend/Observable/BatchJobRunner.swift`, `Views/Library/Batch/*`
  - Backup: `Backend/Observable/BackupManager.swift`, `Utilities/Handlers/BackupCrypto.swift`, `Views/Settings/Backup/*`
  - Auto-sign / queue / cleanup: `AutoSignManager.swift`, `InstallQueue.swift`, `InstallCleanup.swift`, `AppInstaller.swift`
  - Entitlements & Info.plist editing: `EntitlementsManager.swift`, `Utilities/{InfoPlistPlan,PlistDiff}.swift`, `Utilities/MachOEntitlements.swift`, `Utilities/MachOReader.swift`, `Views/Signing/{Entitlements,InfoPlist}/*`, `Views/Signing/Shared/Plist*`
  - Certificates/identity: `CertificateAutoImporter.swift`, `Utilities/IdentityVault.swift`, `Utilities/Handlers/CertificateExporter.swift`, `Utilities/RyukSignAPI.swift`
  - Logging/diagnostics: `Utilities/FileLogger.swift`, `StdoutCapture.swift`, `LogPresentation.swift`, `LogsHistoryView.swift`, `SigningLog.swift`
  - Storage: `StorageManager.swift`, `Views/Settings/Storage/*`
  - Misc: `AppNavigationManager.swift`, `AppStoreHelper.swift`, `AppExtensionEnumerator.swift`, `LinkTagParser.swift`, `TelegramLinkParser.swift`, `ArchiveEngine.swift`, `AppArchiver.swift`
  - Premium/curated repos: `PremiumManager.swift`, `PremiumFilterPreferences.swift`, `Views/Sources/PremiumSettingsView.swift`
  - Tab bar config: `TabBarPreferences.swift`, `Views/Settings/TabBarSettingsView.swift`
- **Entitlements:** need to be re-read from the RyukSign project (path differs); not critical for register.

### 2.5 FlareStore — UNVERIFIED

- Only GitHub hit with the exact name is `acetex/flarestore` — **JavaScript**, 1 star, last pushed 2022, **no license**. It is not an iOS signing/store app and is almost certainly not the intended repository.
- Searches for "FlareStore iOS", "flare ios store" surface only third-party *consumers* of FlareStore (app sources, localization repos), not a source repo. FlareStore appears to be a **closed-source** app.
- **Action required:** ask the user for the exact repository URL, or confirm FlareStore is closed-source/not reusable. **Do not substitute**.

### 2.6 LiveContainer — `LiveContainer/LiveContainer` — AGPL-3.0 — VERIFIED

- **Identity:** "Run iOS apps without actually installing them!" 13,629 stars. App launcher/container, not a signer.
- **Structure:** `LiveContainer/` (main executable: guest Mach-O patching + `dlopen` + entry-point jump), `LiveContainerSwiftUI/` (SwiftUI app list/settings), `LiveProcess/` (helper binary), `LaunchAppExtension/`, `ShareExtension/`, `MultitaskSupport/` (based on FrontBoardAppLauncher), `SideStoreSupport/`, `TweakLoader/`, `litehook/`, `ZSign/`, `OpenSSL/`.
- **Entitlements (`entitlements.xml`):** `get-task-allow`, `application-identifier`, `com.apple.developer.kernel.increased-memory-limit`, healthkit + background delivery, `com.apple.security.application-groups`, and **128 keychain access groups** (`com.kdt.livecontainer.shared.N`).
- **Mechanism (per README):** patch `__PAGEZERO`/`MH_EXECUTE`→`MH_DYLIB`, inject TweakLoader load command, hook `_NSGetExecutablePath`, override `NSBundle.mainBundle`, bypass library validation, `dlopen` guest, jump to entry point. Multi-account via randomized keychain groups.
- **Limitations (documented):** guest containers not sandboxed; entitlements not applied to host; app extensions unsupported; remote push won't work.
- **License:** AGPL-3.0. `THIRD_PARTY_NOTICES.md`-style notices are in FlekDeck, not here.

### 2.7 SideStore — `SideStore/SideStore` — AGPL-3.0 — VERIFIED

- **Identity:** "an untethered, community driven alternative app store for non-jailbroken iOS devices"; a fork of AltStore that doesn't require AltServer. 7,177 stars.
- **Structure:** `SideStore/` (app target), `AltStore/` (fork base), `Dependencies/`, `Shared/`, `SideBackup/` (backup app/extension: `BackupEngine.swift`), `scripts/`.
- **Key technologies:** `EM Proxy` + `LocalDevVPN` (VPN tunnel + loopback/Jitterbug install), `Minimuxer` (on-device usbmuxd replica), `Roxas` (AltStore internal framework), Rust deps.
- **Odysseus already vendors SideSign** from SideStore/Catalyst for the Apple ID signing path (AGPL-3.0). Full SideStore integration (untethered refresh via VPN) is a large, distinct workstream.

### 2.8 Zeus — UNVERIFIED

- No plausible iOS signing/store repository named "Zeus" was found. The closest named repo (`czstore/zeus`) is an HTML page ("free and paid ios mods"), no license, last pushed 2021 — not a source project. Other "Zeus" hits are Bitcoin wallets, security tools, GraphQL clients, etc.
- **Action required:** ask the user for the exact repository URL or app identity. **Do not substitute**.

### 2.9 FlekStore / FlekDeck — `flekstore/FlekDeck` — AGPL-3.0 — VERIFIED

- **Identity:** "a powerful app environment designed to feel like a second operating system inside iOS." 56 stars. README states it is "a modified version of LiveContainer, developed and maintained by FlekStore."
- **Lineage:** LiveContainer derivative. Ships `THIRD_PARTY_NOTICES.md` documenting LiveContainer (AGPL-3.0), Dragula (MIT), StikJIT (MPL-2.0 + AGPL scripts), idevice, etc.
- **Structure:** mirrors LiveContainer (`LiveContainer/`, `LiveContainerSwiftUI/`, `LiveProcess/`, `LaunchAppExtension/`, `ShareExtension/`, `MultitaskSupport/`, `SideStoreSupport/`, `TweakLoader/`, `ZSign/`, `OpenSSL/`) plus FlekStore additions: `LiveContainerSwiftUI/FlekDeck/`, `LiveContainerSwiftUI/FlekStore/`, `LiveContainerSwiftUI/Dragula/`, `LoopbackVPN/`, `StikJITHeadless/`, `Tools/`, `IdevicePairing/`.
- **Distinct features (from README):** redesigned Home Screen with free icon placement + multitasking dock; edit mode/reordering; live multitasking app cards; per-app audio; universal search (Spotlight across apps + repos); redesigned installer with screenshots; parallel downloads with per-icon progress; personalization (wallpapers, glass, bar shapes, haptics); automatic game detection; offline access; iOS 27 / Liquid Glass support; dedicated iPad layout.
- **Related:** `flekstore/LiveContainer-FS` (Apache-2.0) is a LiveContainer+SideStore build for FlekSt0re.com; `flekstore/FlekPair` (desktop pairing-file generator, Tauri) has **no published source** — not reusable.

---

## 3. Lineage / duplication summary

```
AltStore (AGPL-3.0)
  └─ AltSourceKit (MIT, claration) ──────────────► vendored in Odysseus

Feather (GPL-3.0) ───────────────────────────────► Odysseus Feather/ (modified snapshot)
   ├─ FreeSign (GPL-3.0)            (UI/handler lineage)
   ├─ Ksign    (GPL-3.0)   Feather-derived
   ├─ RyukSign (GPL-3.0)   Feather-derived
   └─ (Odysseus) Feather + Odysseus layer

SideStore (AGPL-3.0) ─┬─► SideSign (AGPL-3.0) ────► vendored in Odysseus
                      └─► SideBackup (AGPL-3.0)

LiveContainer (AGPL-3.0) ─┬─► FlekDeck (AGPL-3.0)
                          └─► LiveContainer-FS (Apache-2.0)

FlekPair — source not published
```

**Duplicate-capability note:** Ksign, RyukSign, and Odysseus all independently carry Feather's signing/install/tweak core. LiveContainer and FlekDeck both carry the app-container core. SideStore and Odysseus both carry Apple-ID/dev-portal signing (via SideSign). Feature counts must be de-duplicated across these before being treated as distinct capabilities.

## 4. Open questions for the user

1. **FeatherPlus** — exact repository URL, or confirm it does not exist / is private.
2. **Zeus** — exact repository URL or app identity (there is no obvious public iOS signing project by that name).
3. **FlareStore** — exact repository URL, or confirm it is closed-source and should be excluded.
4. Confirm the intended **LiveContainer/FlekDeck** scope: full app-container hosting (BLOCKED/INVESTIGATE) vs. only reusable sub-components (Mach-O fixups, tweak loader, pairing helpers).
5. Confirm whether **FlekPair** (source not published) should be treated as EXCLUDE.
