# Integration plan

**Audit date:** 2026-10-31 (UTC) · **Revision:** `2a54e3b`
**Status:** proposal — **no production code changed yet.** Awaiting explicit approval before Batch 1.

Batches are ordered by risk and dependency. Each is independently reviewable and revertable. Feature IDs reference `SOURCE_INTEGRATION_MATRIX.md`.

---

## Batch index

| Batch | Feature(s) | IDs | Size | Risk |
|---|---|---|---|---|
| 0 | Audit + docs + foundation checks | — | docs | low |
| **1** | **App update checker (core + UI)** | **R-UPD-01 / F-UPD-01** | **~7 files** | **low** |
| 2 | Tweak Manager | R-TWEAKMGR-01 | large | medium |
| 3 | Batch/bulk signing + bulk install UI | R-BATCH-01, K-BULKSIGN-01, K-BULKINST-01 | medium | medium |
| 4 | Web transfer server (HTTP + WebDAV + auth) | R-WEB-01/02/03 | medium | medium-high (network) |
| 5 | File manager + storage manager | K-FILES-01, R-STORAGE-01 | large | medium |
| 6 | Live Activities + enhanced downloads | R-LIVEACT-01/02, R-DOWNLOAD-01 | medium | medium (extension target) |
| 7 | Editors + auto-import + tab config + helpers | R-ENT-01, R-PLIST-01, R-CERTAUTO-01, R-TABBAR-01, K-UTTYPE-01, K-SHORTCUT-01 | medium | medium |
| 8 | App container (LiveContainer/FlekDeck) | LC-CORE-01 + dependents | very large | **blocked — separate gate** |
| 9 | SideStore refresh / backup | SS-REFRESH-01, SS-BACKUP-01 | very large | **investigate — separate** |

Out of scope for all batches unless explicitly approved: FeatherPlus (**EXCLUDE** — verified Feather fork, no distinct capability); Zeus and FlareStore (**closed-source**, no public source repo — concept-reference only); FlekPair (source not published).

> **Upstream identity resolution (2026-10-31):** all nine named identities are resolved in `UPSTREAM_SOURCE_REGISTER.md`. FeatherPlus (`TomerGamerTV/FeatherPlus`, GPL-3.0, `9af4713`) adds no capability Odysseus lacks. Zeus (`getzeus.app`) and FlareStore (`flarestore.app`) publish no source — their features are inventoried as concept-only in `SOURCE_INTEGRATION_MATRIX.md`.

---

# Batch 1 — App update checker (first batch)

## Objective & feature IDs
- **Objective:** tell the user when an app in their Library has a newer version available in one of their sources, with per-app ignore and a manual "Check Now".
- **IDs:** `R-UPD-01` (primary, RyukSign `AppUpdateChecker` + `SkippedUpdatesManager`), `F-UPD-01` (reference, Feather `UpdateManager` + `Storage+SourceMetadata`).

## Included / excluded scope
- **Included:** version comparison; matching Library apps to source apps; per-app skip list; a Library update affordance; a Settings → Updates screen; unit tests for comparison/skip/matching.
- **Excluded:** automatic downloading/updating; self-update (`R-UPD-02`); a new Core Data `AppSourceMetadata` entity (deferred to a Batch 1b if provenance-carrying across re-sign is needed); background scheduling beyond the existing source-refresh cadence.

## Source repositories / commits / original paths
- `faroukbmiled/RyukSign` @ `844466cee6f212291913ba5216f8f19a9c016dea` (branch `main`)
  - `RyukSign/Backend/Observable/AppUpdateChecker.swift`
  - `RyukSign/Backend/Observable/SkippedUpdatesManager.swift`
- `claration/Feather` @ `7078b053c0af262809a48e4d3898d42b0d35fedf` (branch `main`)
  - `Feather/Backend/Observable/UpdateManager.swift`
  - `Feather/Backend/Storage/Storage+SourceMetadata.swift`
- License: GPL-3.0 (both). Preserve notices; add to `license_plist.yml` if new third-party files are vendored (none are — this is an ADAPT of in-repo Feather-derived code).

## Exact Odysseus files

### Create
| Path | Action | Content |
|---|---|---|
| `Feather/Backend/Odysseus/ODVersionCompare.swift` | create | Pure version-comparison helper ported from RyukSign `AppUpdateChecker.isNewerVersion(_:than:)`. |
| `Feather/Backend/Odysseus/ODSkippedUpdatesManager.swift` | create | Per-app skip list, ported from RyukSign `SkippedUpdatesManager.swift` (UserDefaults-backed). |
| `Feather/Backend/Odysseus/ODUpdateChecker.swift` | create | `ODAppUpdate` model + `ODUpdateChecker` ObservableObject; matching + comparison orchestration. Adapted from RyukSign `AppUpdateChecker` + Feather `UpdateManager`. |
| `Feather/Views/Odysseus/Settings/ODUpdatesSettingsView.swift` | create | Settings screen: enable/disable, Check Now, last-checked date, skipped-app list. |
| `OdysseusTests/ODUpdateCheckerTests.swift` | create | Unit tests for version compare, skip manager, and matching. |

### Modify
| Path | Action | Change |
|---|---|---|
| `Feather/Backend/Storage/Storage+Shared.swift` | modify | Add `sourceURL` to `AppInfoPresentable` (default `nil`) and witness it on `Signed`/`Imported` from the Core Data `source` attribute, so the checker can match an app to its source repository. |
| `Feather/Views/Odysseus/Library/ODLibraryView.swift` | modify | Show an update indicator/button on apps that have an available update. |
| `Feather/Views/Odysseus/Settings/ODSettingsView.swift` | modify | Add a "Updates" row navigating to `ODUpdatesSettingsView`. |
| `Feather/FeatherApp.swift` | modify (optional) | Trigger `ODUpdateChecker.shared.checkForUpdates(...)` on the existing source-refresh cadence / active-scene path. **TO VERIFY** exact hook point against current `AppDelegate`/`onChange` code. |

## Phase 5 — file-by-file plan (Batch 1)

### 1. `Feather/Backend/Odysseus/ODVersionCompare.swift` — CREATE
- **Upstream:** RyukSign `AppUpdateChecker.swift` (private `isNewerVersion`), commit `844466c`.
- **Symbols:** `enum ODVersionCompare { static func components(_ version: String) -> [Int]; static func isNewer(_ new: String, than old: String) -> Bool }`.
- **Behavior:** split on `.`, parse Ints, compare component-wise with missing components treated as 0; return true on first strictly-greater component, false otherwise. Empty/unparsable → false.
- **Dependencies:** Foundation only.
- **Tests:** `1.2 > 1.1`; `2.0 > 1.9.9`; `1.0 == 1.0`; `1.0 < 1.1`; `1.0.0 == 1.0`; non-numeric input.
- **Risk/rollback:** pure function; delete file to revert.

### 2. `Feather/Backend/Odysseus/ODSkippedUpdatesManager.swift` — CREATE
- **Upstream:** RyukSign `SkippedUpdatesManager.swift`, commit `844466c`.
- **Symbols:** `@MainActor final class ODSkippedUpdatesManager: ObservableObject { static let shared; static let defaultsKey = "Odysseus.skippedUpdateBundleIDs"; @Published private(set) var bundleIDs: Set<String>; static var persisted: Set<String>; var sortedBundleIDs: [String]; func isIgnored(_:); func ignore(_:); func resume(_:); func toggle(_:) }`; `extension Notification.Name { static let odysseusSkippedUpdatesChanged }`.
- **Behavior:** mute/unmute bundle IDs in UserDefaults; post a notification on change. `persisted` is a thread-safe snapshot for off-main reads.
- **Dependencies:** Foundation, Combine.
- **Tests:** ignore/resume/toggle persistence; `isIgnored` on empty/nil.
- **Risk/rollback:** isolated; delete to revert. Preference key is Odysseus-namespaced (not Feather's) to avoid collisions.

### 3. `Feather/Backend/Odysseus/ODUpdateChecker.swift` — CREATE
- **Upstream:** RyukSign `AppUpdateChecker.swift` (`checkForUpdates`, `computeUpdate`, `findInstalledApp`, `hasUpdate`) and Feather `UpdateManager.swift` (`checkForUpdates`, `_findUpdates`, URL normalization), commits `844466c` / `7078b05`.
- **Symbols:**
  - `struct ODAppUpdate: Identifiable, Equatable { let id: String; let appUUID: String; let appName: String; let bundleIdentifier: String; let localVersion: String?; let remoteVersion: String; let downloadURL: URL; let sourceURL: URL }`
  - `@MainActor final class ODUpdateChecker: ObservableObject { static let shared; @Published private(set) var updates: [String: ODAppUpdate]; @Published private(set) var isChecking: Bool; @Published private(set) var lastCheckedDate: Date?; func update(for app: AppInfoPresentable) -> ODAppUpdate?; func checkForUpdates(sources: [AltSource], localApps: [AppInfoPresentable]) async; func clearCache() }`
- **Behavior / control flow:**
  1. Guard `!isChecking`; set `isChecking = true`; `defer { isChecking = false; lastCheckedDate = Date() }`.
  2. Fetch each source repository via `NBFetchService().fetch(from:)` (AltSourceKit), skipping failures.
  3. For each local app: determine `sourceURL` (from `AppInfoPresentable.sourceURL`); find the matching source by normalized URL; find the repository app whose `id == app.identifier`; skip if missing.
  4. Skip if `ODSkippedUpdatesManager.shared.isIgnored(identifier)`.
  5. Compare `ODVersionCompare.isNewer(remoteVersion, than: localVersion)`; if true, record `ODAppUpdate`.
  6. Assign `updates` on the main actor.
- **Concurrency:** repository fetches run off-main via `withCheckedContinuation` over `NBFetchService`; results re-enter the main actor. `updates` mutated only on main.
- **Input validation:** ignore empty identifier/version; normalize source URLs (scheme/host lowercased, fragment dropped, trailing slash trimmed) as in Feather `UpdateManager._normalizedSourceURL`.
- **Error handling:** a failed source fetch is skipped (logged), not fatal; cancellation propagates.
- **Dependencies:** Foundation, AltSourceKit, OSLog, NimbleExtensions (localized strings).
- **Tests:** matching by identifier + source URL; skip-list exclusion; no-update case; source-fetch-failure tolerance (using a protocol seam if needed).
- **Risk/rollback:** new file; delete to revert. The `AppInfoPresentable.sourceURL` addition is additive (default `nil`).

### 4. `Feather/Backend/Storage/Storage+Shared.swift` — MODIFY
- **Existing symbol:** `protocol AppInfoPresentable` (lines ~133–141); `extension Signed: AppInfoPresentable`; `extension Imported: AppInfoPresentable`.
- **Change:** add `var sourceURL: URL? { get }` requirement with a protocol-extension default returning `nil`; provide witnesses on `Signed`/`Imported` returning the Core Data `source` attribute (`source as? URL`).
- **Behavior:** enables the checker to tie a Library app to its source repository without a new entity.
- **Risk/rollback:** additive; revert by removing the requirement and witnesses.

### 5. `Feather/Views/Odysseus/Library/ODLibraryView.swift` — MODIFY
- **Existing symbol:** app row rendering (`_appRow`/cell) and the `@ObservedObject _statusStore` pattern.
- **Change:** observe `ODUpdateChecker.shared`; for each app with `update(for:) != nil`, show an "Update" badge/button that re-runs the Get flow for the remote `downloadURL` (via `ODSignPipeline.get`/`DownloadManager.startDownload`).
- **TO VERIFY:** exact cell builder location and how `ODGetButton` is reused.
- **Risk/rollback:** small view diff; revert by removing the badge.

### 6. `Feather/Views/Odysseus/Settings/ODSettingsView.swift` — MODIFY
- **Change:** add one `NavigationLink` row → `ODUpdatesSettingsView()`.
- **Risk/rollback:** one row; revert by deletion.

### 7. `Feather/Views/Odysseus/Settings/ODUpdatesSettingsView.swift` — CREATE
- **Symbols:** `struct ODUpdatesSettingsView: View` with a toggle (enabled), a "Check Now" button, last-checked date, and a list of skipped bundle IDs with resume buttons.
- **Behavior:** calls `ODUpdateChecker.shared.checkForUpdates(sources: Storage.shared.getSources(), localApps: …)`; reads/writes `ODSkippedUpdatesManager.shared`.
- **Risk/rollback:** new file; delete to revert.

### 8. `OdysseusTests/ODUpdateCheckerTests.swift` — CREATE
- **Cases:** version comparison (≥6 cases); skip manager persistence + toggle; update matcher with a fake repository and a fake `AppInfoPresentable`; no-match and no-update cases.
- **Note:** matching tests should avoid Core Data where possible by testing the pure matcher; if the checker is not decomposed, mark those cases **NOT RUN** until a seam exists.
- **Build status:** tests can only run on macOS/Xcode; this sandbox is Linux → **NOT RUN** here.

## Dependencies & project-setting changes
- None required for Batch 1. AltSourceKit (`NBFetchService`) is already a dependency. No new entitlements.

## Architecture / data-flow changes
- Additive: a new backend manager and a `sourceURL` accessor. No change to the signing pipeline, persistence model, or install transports.

## Security / privacy / migration
- The checker fetches source repositories (already fetched by Odysseus). No new credentials. Skip list is local UserDefaults. No migration.

## Acceptance criteria & tests
1. `ODVersionCompare.isNewer` correct on the documented matrix.
2. `ODSkippedUpdatesManager` persists across instances and excludes apps from the update set.
3. `ODUpdateChecker` marks an app as updated only when a newer version exists in the app's source and it is not skipped.
4. A source fetch failure does not crash the check or block others.
5. Library shows an update affordance; Settings → Updates works.
6. Existing tests remain green (`xcodebuild test`).

## Rollback plan
- Revert the four Batch-1 view/backend files and the `Storage+Shared.swift` witness (one-line-ish diff). No migration, no data written, so rollback is a clean revert.

## User-visible behavior & limitations
- Users see an "Update" indicator on Library apps with newer source versions, and can check/mute in Settings.
- Limitations: matching is by bundle ID within the app's recorded source; apps imported without a source URL or signed with a changed bundle ID may not match (documented). No automatic update download in this batch.

## Task-specific working branch
- `feat/app-update-checker` (local), to be created from `arena/088597d5-odysseus` before implementation.

## Proposed PR / commit (prepare only — do not create)
- **PR title:** `feat(updates): add app update checker`
- **PR description:** Adds on-device update detection comparing Library apps against their source repositories, with a per-app skip list and a Settings screen. Ported/adapted from RyukSign `AppUpdateChecker`/`SkippedUpdatesManager` (GPL-3.0) and Feather `UpdateManager` (GPL-3.0). No new dependencies or entitlements. Includes unit tests for version comparison, skip persistence, and matching.
- **Branches:** target `arena/088597d5-odysseus`; working `feat/app-update-checker`.
- **Conventional Commit:** `feat(updates): add app update checker`
- **Changelog/release notes:** "Library now shows when a newer version is available in your sources. Manage updates and mute individual apps in Settings → Updates."
- **Out of scope:** automatic updating, self-update, cross-source provenance metadata.

## Verification statuses after Batch 1 (target)
- `SOURCE_VERIFIED` ✓ (RyukSign/Feather code inspected)
- `LICENSE_REVIEWED` ✓ (GPL-3.0; no new vendored files)
- `IMPLEMENTED` — pending approval
- `BUILD_VERIFIED` — pending (macOS/Xcode only)
- `AUTOMATED_TESTED` — pending
- `SIMULATOR_TESTED` / `PHYSICAL_DEVICE_TESTED` — not planned for this batch
- `DOCUMENTED` — this plan + matrix

---

# Batch 2 — Tweak Manager (R-TWEAKMGR-01) — summary

- **Objective:** manage a library of tweaks (`.dylib`/`.deb`/`.framework`/`.bundle`/`.appex`) with per-tweak metadata and inject selected tweaks at sign time (or into an existing signed app).
- **Source:** RyukSign @ `844466c` — `Backend/Observable/TweakManager.swift`, `TweakModels.swift`, `Utilities/Handlers/TweakAnalyzer.swift`, `TweakExtractor.swift`, `Views/Tweaks/*`.
- **Files:** new `Backend/Odysseus/ODTweak*.swift`, `Views/Odysseus/Tweaks/*`; modify `TweakHandler.swift` to consume the library; possibly a `Tweak` Core Data entity.
- **Acceptance:** import/organize/inspect tweaks; select tweaks per sign; injection into extensions; ElleKit/Substrate detection.
- **Risk:** medium (touches injection path). Rollback: revert `TweakHandler` changes + delete new files.

# Batch 3 — Batch/bulk signing (R-BATCH-01) — summary
- **Source:** RyukSign `BatchJobRunner.swift`, `InstallQueue.swift`, `InstallCleanup.swift`, `Views/Library/Batch/*`; Ksign `Views/Signing/BulkSigningView.swift`, `BulkInstall*View.swift`.
- **Integration:** a queue in front of `ODSignPipeline.sign`; reuse `ODSignPipeline` per job.
- **Acceptance:** sign N apps with one identity; per-job progress/cancellation; no partial Library records on failure.
- **Risk:** medium.

# Batch 4 — Web transfer server (R-WEB-01/02/03) — summary
- **Source:** RyukSign `Backend/Server/WebManagerServer{,+HTTP,+WebDAV}.swift`, `Backend/Observable/WebManager.swift`, `Views/Settings/Web Manager/WebManagerView.swift`.
- **Integration:** extend the Vapor `ServerInstaller` with HTTP + WebDAV routes; loopback-only; optional password.
- **Security gate:** bind loopback, auth required, path confinement to app-owned directories, no TLS downgrade.
- **Risk:** medium-high (network-facing within the device).

# Batch 5 — File manager + storage manager (K-FILES-01, R-STORAGE-01) — summary
- **Source:** Ksign `Views/Files/*` (HexEditor, PlistEditor, TextEditor, QuickLook, CertificateService); RyukSign `StorageManager.swift`, `Views/Settings/Storage/*`.
- **Integration:** a file browser scoped to Odysseus's Documents trees + imports; storage detail screen.
- **Risk:** medium (large UI). Security: file access confined to app sandbox.

# Batch 6 — Live Activities + enhanced downloads (R-LIVEACT-01/02, R-DOWNLOAD-01) — summary
- **Source:** RyukSign `DownloadManager+LiveActivity.swift`, `DownloadProgressAttributes.swift`, `Backend/AppIntents/DownloadControlIntent.swift`, `DownloadSpeedTracker.swift`, `Views/Download/*`.
- **Integration:** new Widget Extension target; extend `DownloadManager`.
- **Risk:** medium; requires a new app-extension target + entitlements review.

# Batch 7 — Editors + auto-import + tab config + helpers (R-ENT-01, R-PLIST-01, R-CERTAUTO-01, R-TABBAR-01, K-UTTYPE-01, K-SHORTCUT-01) — summary
- **Source:** RyukSign entitlements/Info.plist editors, `CertificateAutoImporter.swift`, `TabBarPreferences.swift`; Ksign `Extensions/UTType/*`, `Extensions/FileManager/*`.
- **Integration:** extend `Options` and `SigningHandler`; add settings rows.
- **Risk:** medium.

# Batch 8 — App container (LC-CORE-01) — BLOCKED / separate gate
- Not started. Requires: security review, entitlements, a second executable + extensions, and an explicit approval. See `ARCHITECTURE.md` §6.

# Batch 9 — SideStore refresh / backup (SS-REFRESH-01, SS-BACKUP-01) — INVESTIGATE / separate
- Not started. Large, orthogonal transport (VPN/Jitterbug). Decide whether to adopt alongside or instead of the server/pairing install paths.

---

## Verification rules reminder
- Build ≠ signing works; simulator ≠ device. Mark `NOT RUN` when not run. Never fabricate results.
- Each batch must update `SOURCE_INTEGRATION_MATRIX.md`, `ARCHITECTURE.md`, `BASELINE_AUDIT.md`, and add a changelog entry.
- Stop and report if a build, test, license, security, or compatibility gate fails.
