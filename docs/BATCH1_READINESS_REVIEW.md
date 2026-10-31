# Batch 1 readiness review

**Review date:** 2026-10-31 (UTC)
**Reviewed package:** `docs/BASELINE_AUDIT.md`, `docs/SOURCE_INTEGRATION_MATRIX.md`, `docs/UPSTREAM_SOURCE_REGISTER.md`, `docs/INTEGRATION_PLAN.md`, `docs/ARCHITECTURE.md`
**Working tree reviewed:** branch `arena/b50aa4f2-odysseus`, HEAD `c2040b04f22f6eaab67211f3a5cd62aad91970c3` (identical to `origin/master`)
**Production code changed by this review:** **none.** This document and the four docs listed above are the only files touched.

---

## Verdict

| # | Point raised | Answer |
|---|---|---|
| 1 | Confirm branch and baseline | **Corrected.** The docs name a branch and revision that are no longer the working tree. Baseline restated in §1; app-code content is provably identical to the audited revision. |
| 2 | Reconcile feature counts and statuses | **Corrected.** Every count in the matrix summary was wrong (17/43/60 → 18/61/79). "Implemented" is replaced by a status model that separates code-present, new-in-branch, and test evidence. §2. |
| 3 | Check the update-checker plan against the data model | **Plan does not work as written.** The proposed `sourceURL` witness would compile and always return `nil`, so no app would ever match. Rescoped plan in §6. §3. |
| 4 | License/provenance per copied file | **Specified.** Exact attribution header for each file, plus README credit and register table. §4. |
| 5 | Batch 1 remains a proposal | **Held.** No production edits. Batch 1 is re-proposed as an 11-file plan in §6 and is **not approved**. Three decisions are needed (§7). |

**Bottom line:** approve Batch 1 only after the §7 decisions are answered. Do not approve the rest of the roadmap.

---

## 1. Branch and baseline

### 1.1 What the docs said vs what exists

| Fact | Docs claimed | Verified now | How |
|---|---|---|---|
| Working branch | `arena/088597d5-odysseus` | **`arena/b50aa4f2-odysseus`** | `git branch` |
| HEAD | `2a54e3bf…` | **`c2040b04f22f6eaab67211f3a5cd62aad91970c3`** | `git rev-parse HEAD` |
| `master` | `2a54e3bf…` | **`c2040b04…`** (identical to HEAD and to `origin/master`) | `git rev-parse`, `git ls-remote origin refs/heads/master` |
| History | single squashed commit | single squashed commit; **`2a54e3b` is no longer a reachable commit object** | `git cat-file -t 2a54e3b` → "could not get object info" |
| Tag `nightly` | `→ 2a54e3b` | still `→ 2a54e3b` **on the remote**; the local clone has no tags | `git ls-remote --tags origin` |
| Submodules | not initialized | still not initialized (`git submodule status` shows `-` for both) | `git submodule status` |

The repository history was squashed again when this sandbox was created. `arena/088597d5-odysseus` still exists on the remote (`fe0f37e`) but is no longer the tree that will be modified. Any instruction that references that branch — including the old "create `feat/app-update-checker` from `arena/088597d5-odysseus`" line — is stale and has been removed.

### 1.2 The app code is nonetheless the audited code

Verified with the GitHub tree API against the audited revision and a content comparison of all 27 top-level paths:

- `git rev-parse HEAD:Feather` → `c996af8e9f653ea3e668558371bd0e4603516f22`
- `gh api repos/raynmahbub/Odysseus/git/trees/2a54e3b` → `Feather` entry = `c996af8e9f653ea3e668558371bd0e4603516f22`

**All 27 top-level entries are byte-identical between `2a54e3b` and `c2040b0` except `docs/`.** So the audit's findings remain valid for the code; only the identifiers needed correcting.

### 1.3 CI evidence (this closes a gap the audit left open)

The audit recorded CI for `2a54e3b` as **UNVERIFIED**. It is now verified:

| Run | Commit | Branch | Result |
|---|---|---|---|
| `41198043032` | `2a54e3b` | `master` | **success** — job "Build unsigned Odysseus.ipa" (simulator tests + IPA + `scripts/verify_ipa.sh`), 2026-10-31T11:43Z |
| `41219757550` | `fe0f37e` (docs PR #4) | `arena/088597d5-odysseus` | **success** — same job, on the audit package itself |

No CI run exists for the squashed `c2040b0` SHA, because squashing did not trigger one on `master`. Since the only difference between `fe0f37e`/`c2040b0` and the green `2a54e3b` tree is `docs/`, the build/tests result carries over. Cite `41198043032` and `41219757550`, not the SHA, when asked whether the baseline is green.

**Still impossible in this sandbox:** `xcodebuild`, `swiftc`, XCTest, `codesign`. Linux host, no Apple toolchain, empty submodules. Any Batch 1 test result produced here must be marked `NOT RUN`.

---

## 2. Feature counts and statuses

### 2.1 Counts — all three summary numbers were wrong

| Quantity | Docs said | Actual | Method |
|---|---|---|---|
| Existing Odysseus capabilities (Part 1) | 17 | **18** | row count |
| Candidate/blocked/excluded capabilities (Part 2) | 43 | **61** | row count |
| Total inventoried | 60 | **79** | row count |

Part 2 by group: A (Feather) **2**, B (Ksign) **13**, C (RyukSign) **25**, D (LiveContainer/FlekDeck) **14**, E (SideStore) **3**, F (unverifiable) **4**.

By classification (Part 2 only): adoptable **35** (ADAPT 22, CHERRY-PICK 9, COPY/ADAPT 3, CHERRY-PICK/ADAPT 1 — the two update-checker rows are counted as `ADAPT` after this review); INVESTIGATE **8**; BLOCKED **13**; EXCLUDE **2**; EXCLUDE/INVESTIGATE **1**; CONCEPT-ONLY **2**. Part 1 is 18 KEEP.

### 2.2 Status model

"Implemented" conflated three different facts. `SOURCE_INTEGRATION_MATRIX.md` now uses this vocabulary, and no row may use a stronger claim than its evidence:

| Status | Meaning | Evidence required |
|---|---|---|
| `CODE_PRESENT` | Source exists in the baseline tree and is reachable from the app | file path in the tree |
| `NEW_IN_BRANCH` | Code added on this branch | diff from `master` |
| `UNIT_TESTED` | Automated test exercises the behaviour | named test case |
| `BUILD_VERIFIED` | Compiled and packaged by CI at a named commit | CI run id |
| `SIMULATOR_TESTED` / `PHYSICAL_DEVICE_TESTED` | Exercised at runtime | run log / device note |
| `NOT_RUN` | No evidence | — |

At `c2040b0`: **`NEW_IN_BRANCH` = 0** for every capability, and **`PHYSICAL_DEVICE_TESTED` = 0**. The 16 existing XCTest cases cover four areas only:

| Test file | Cases | Covers |
|---|---|---|
| `ODZsignOutcomeTests.swift` | 5 | OD-SIG-01 (`ODZsignOutcome.validate` only — not signing itself) |
| `ODOCSPCoreTests.swift` | 2 | OD-CERT-01 (parser binding) |
| `ODOCSPFreshnessTests.swift` | 2 | OD-CERT-01 (freshness window) |
| `ODOCSPResponderAuthorizationTests.swift` | 3 | OD-CERT-01 (responder authorization) |
| `StorageConcurrencyTests.swift` | 3 | persistence + OD-LIB-01 (concurrent writes, failed store load, signing defaults) |
| `ODAppleIDMaterialCleanupTests.swift` | 1 | OD-APP-01 (stale temp-material cleanup only) |

So of 18 existing capabilities, **4 have partial automated coverage** (OD-SIG-01, OD-APP-01, OD-LIB-01, OD-CERT-01), 1 of those is fully covered (OD-CERT-01), and **14 have none**. Discover, sources, install transports, tweaks, and the UI have no automated tests at all, and nothing is device-verified. The matrix has been updated accordingly rather than relabelled wholesale.

---

## 3. The update-checker plan against the current data model

### 3.1 Conforming types — verified

`AppInfoPresentable` lives in `Feather/Backend/Storage/Storage+Shared.swift` (lines 134–141) with exactly two conformers: `Signed` and `Imported`. `AnyApp` only wraps a base value. Adding a defaulted `sourceURL` requirement would be source-compatible.

### 3.2 The proposed witness would always be nil — blocking

The plan said: *"witness it on `Signed`/`Imported` from the Core Data `source` attribute."* That attribute exists on both entities, but **nothing writes it**:

- `Storage+Imported.addImportedAsync` accepts `source: URL? = nil`, and the only production caller — `AppFileHandler.addToDatabase()` (`Feather/Utilities/Handlers/AppFileHandler.swift:119`) — does not pass it.
- `Storage+Signed.addSignedAsync` has **no `source` parameter at all**, so `Signed.source` is never assigned.

Result: `sourceURL` on every Library record would be `nil`, so the planned "find the matching source by normalized URL → find the repository app" step would find nothing, for every app, every time. Batch 1 as written would ship a silent no-op. This is the single most important correction in this review.

### 3.3 Upstream already solved this — the plan skipped the write path

- `claration/Feather` @ `7078b05`: `AppInfoPresentable` **already declares `source: URL?`**, and `addImported`/`addSigned` write it. Feather additionally has a dedicated `AppSourceMetadata` entity and a `SourceAppProvenance` struct, written from `AppFileHandler.addSourceMetadata(...)` and copied by `SigningHandler.copySourceMetadata(...)`; `UpdateManager` matches on the stored repository URL plus the source app identifier, falling back to `localApp.source`.
- `faroukbmiled/RyukSign` @ `844466c`: `AppUpdateChecker` matches on `identifier` **or `originalIdentifier`** (an attribute Odysseus does not have) **or the app name** (case-insensitive). Its `SkippedUpdatesManager` is the useful part; its matcher is the risky part.

So Odysseus's snapshot dropped both the protocol property and the write path, and the plan was re-deriving upstream's design while skipping the part that makes it work.

### 3.4 Additional defects found in the upstream code (must not be copied into Odysseus)

1. **Core Data queue violation.** `AppUpdateChecker.precomputeAllUpdates` iterates `FetchedResults<Signed>`/`FetchedResults<Imported>` inside `Task.detached`. `FetchedResults` is not safe off its context queue. Odysseus's remediation deliberately removed exactly this class of bug (`BASELINE_AUDIT` §4.3), so the adaptation must snapshot to value types on the main actor first.
2. **Name matching causes false positives.** RyukSign treats an app as installed when the *name* matches, even if the bundle ID differs. Two different apps with the same display name would be cross-linked, and the "Update" button would then download a different app. Do not adopt name matching.
3. **Version comparison is component-wise with `compactMap { Int($0) }`.** Non-numeric components are silently dropped ("1.0b" → `[1, 0]`), and unparsable input degrades to `[]`. That is acceptable, but it must be documented and tested instead of described as "returns false on unparsable input" (it returns false only because `[]` compares equal to `[]`).

### 3.5 Bundle-ID modifications break identifier matching (new)

`ODPrefs.adjustedBundleID` prepends/appends the configured prefix and suffix deterministically, so those can be stripped back off. **PPQ protection cannot**: `Options.ppqString` is a random string generated per install (`OptionsManager.randomString()`), so an app signed with PPQ has an identifier that cannot be mapped back to its source identifier without stored provenance. Any plan that claims "matching is by bundle ID" must state that PPQ-signed apps (and prefix/suffix-signed apps, unless the strip heuristic is used) will not match in v1.

### 3.6 A better integration point already exists

`ODCatalogStore` (`Feather/Views/Odysseus/Discover/ODCatalogStore.swift`) already holds the deduplicated, hidden-source-filtered catalog of every loaded source, refreshes on the configured cadence, and rebuilds on source or settings change. The checker should consume that catalog instead of calling `NBFetchService` again — no second fetch path, no second cache, no duplicated error handling. `ODSignPipeline.get(_:)` already implements the download → sign → install flow for an `ASRepository.App`, so the "Update" action reuses it unchanged.

### 3.7 Schema cost of the "correct" design

Provenance needs persistence (an attribute or an entity). The model has a single unversioned `.xcdatamodel` inside `Feather.xcdatamodeld` (`_XCCurrentVersionName = Feather.xcdatamodel`). An additive attribute would migrate via `NSPersistentStoreDescription` defaults, but the repository has no model-version history and no migration test. Changing the schema inside a "low-risk, ~7 files" batch is not justified; it is a separate batch with its own migration proof (§6.4).

**Decision taken in the re-proposed plan:** Batch 1 makes **no schema change and no `AppInfoPresentable` change**. Provenance (`AppSourceMetadata`/`originalIdentifier`) is Batch 1b, separately approvable.

---

## 4. License and provenance per reused file

### 4.1 Licensing position — verified

- `LICENSE` in the repository is **GPL-3.0** (verbatim).
- RyukSign (`844466c`) and Feather (`7078b05`) are **GPL-3.0**. Adapting their code into a GPL-3.0 project is compatible; the derived files stay GPL-3.0.
- No AGPL code is involved in Batch 1. `SideSign/` (AGPL-3.0) is untouched, so the existing GPL §13 combination note in `README.md` is unaffected.
- Neither upstream file carries a per-file copyright line: RyukSign files have only `//  AppUpdateChecker.swift / //  RyukSign`; Feather files have `//  Created by …`. GPL-3 §5 still requires preserving notices, so attribution is carried in the file header rather than invented.
- The repository already has a convention for ported code: `Feather/Utilities/MachO/MachOUtils.m` records the upstream URL, the exact commit, and the license inline. Batch 1 follows it.

### 4.2 Exact notice handling

Every created file that contains adapted upstream code gets this header, with the file-specific path and commit filled in (no trailing whitespace, tabs consistent with the file):

```
//
//  <FileName>.swift
//  Odysseus
//
//  Adapted from <Project> (GPL-3.0) — <upstream file>, <symbols>.
//  Upstream: https://github.com/<owner>/<repo>/blob/<40-char commit>/<path>
//  Modified for Odysseus, 2026-10-31: <one-line summary of the change>.
//  Odysseus is licensed under the GPL-3.0 — see LICENSE.
//
```

Per file:

| Odysseus file | Upstream | Commit | Header line 5 |
|---|---|---|---|
| `ODVersionCompare.swift` | `RyukSign/Backend/Observable/AppUpdateChecker.swift` (`isNewerVersion`) | `844466cee6f212291913ba5216f8f19a9c016dea` | type name, access level, documented non-numeric handling |
| `ODSkippedUpdatesManager.swift` | `RyukSign/Backend/Observable/SkippedUpdatesManager.swift` | `844466c` | Odysseus-namespaced defaults key and notification, injectable `UserDefaults` for tests |
| `ODUpdateChecker.swift` | `RyukSign/…/AppUpdateChecker.swift` (`hasUpdate`, `computeUpdate`) + `Feather/Backend/Observable/UpdateManager.swift` | `844466c` / `7078b053c0af262809a48e4d3898d42b0d35fedf` | reads `ODCatalogStore` instead of re-fetching; snapshots to value types instead of passing `FetchedResults` across queues; no name matching |
| `ODUpdatesSettingsView.swift` | none — new UI | — | no attribution header; add `//  Odysseus` only |
| three test files | none — original work | — | no attribution header |

Also required in the same change:

1. `README.md` → **Credits**: add `- [RyukSign](https://github.com/faroukbmiled/RyukSign): app update checker (adapted)`. Keep the existing Feather line; no new license paragraph is needed.
2. `docs/UPSTREAM_SOURCE_REGISTER.md` → new §5 table "Adopted code — per-file provenance", one row per adopted file (Odysseus path, upstream repo, upstream path, commit, license, modification, notice location). This is the durable record; it is what an auditor reads.
3. `license_plist.yml` → **no change**. Nothing is vendored, no package is added, and the GPL-3.0 obligation is already satisfied by the repository `LICENSE` plus the file headers. Adding an entry here would imply a third-party component that does not exist.
4. Do **not** copy upstream `LICENSE` files into the tree and do **not** paste GPL text into new files.

---

## 5. Batch 1 status after this review

- Batch 1 is **still a proposal**. No production file was created or modified.
- Files changed by this review: `docs/BATCH1_READINESS_REVIEW.md` (new), `docs/BASELINE_AUDIT.md`, `docs/SOURCE_INTEGRATION_MATRIX.md`, `docs/UPSTREAM_SOURCE_REGISTER.md`, `docs/INTEGRATION_PLAN.md` (and a revision line in `docs/ARCHITECTURE.md`).
- The previously approved-looking 8-file plan is withdrawn and replaced by §6.

---

## 6. Final Batch 1 plan (re-proposed — awaiting approval)

### 6.1 Objective and IDs

Detect when an app in the Library has a newer version in one of the user's sources, with a per-app mute list, a Library affordance, and a Settings screen. No automatic updates, no self-update, no schema change.

IDs: `R-UPD-01` (primary), `F-UPD-01` (reference). Both reclassified in the matrix from `CHERRY-PICK` to **`ADAPT`**, because neither upstream design can be taken as-is (§3.3–3.5).

### 6.2 Files — create (7)

| # | Path | Upstream / notice | Contents |
|---|---|---|---|
| 1 | `Feather/Backend/Odysseus/ODVersionCompare.swift` | RyukSign `844466c` | `enum ODVersionCompare { static func components(_:) -> [Int]; static func isNewer(_:than:) -> Bool; static func highest(_:) -> String? }`. Splits on `.`, keeps only `Int`-parsable components, compares component-wise with missing components as 0. Empty/unparsable on either side → `false`. Foundation only. |
| 2 | `Feather/Backend/Odysseus/ODSkippedUpdatesManager.swift` | RyukSign `844466c` | `@MainActor final class ODSkippedUpdatesManager: ObservableObject`; `static let shared`; `static let defaultsKey = "Odysseus.updates.skippedBundleIDs"`; `init(defaults: UserDefaults = .standard)`; `@Published private(set) var bundleIDs: Set<String>`; `static func persisted(in:) -> Set<String>`; `sortedBundleIDs`; `isIgnored(_:)`, `ignore(_:)`, `resume(_:)`, `toggle(_:)`, `resumeAll()`. Posts `.odysseusSkippedUpdatesChanged`. Key and notification names are Odysseus-namespaced. |
| 3 | `Feather/Backend/Odysseus/ODUpdateChecker.swift` | RyukSign `844466c` + Feather `7078b05` | `struct ODAppUpdate: Identifiable, Equatable { let appUUID, appName, bundleIdentifier, localVersion, remoteVersion, sourceName: String; let sourceID: String; let remoteApp: ASRepository.App; var id: String { appUUID } }`; `struct ODLocalApp: Equatable { uuid, name, identifier, version: String?; isSigned: Bool }`; `struct ODUpdateCandidate: Equatable { bundleIdentifier, name, version: String; sourceID, sourceName: String; app: ASRepository.App }`; `@MainActor final class ODUpdateChecker: ObservableObject` with `static let shared`, `@Published private(set) var updates: [String: ODAppUpdate]`, `@Published private(set) var isChecking: Bool`, `@Published private(set) var lastChecked: Date?`, `func update(for app: AppInfoPresentable) -> ODAppUpdate?`, `func refresh(candidates: [ODUpdateCandidate], localApps: [ODLocalApp])`, `func clear()`. Matching is a **pure static function** `static func match(candidates:localApps:ignored:identifierPrefix:identifierSuffix:) -> [ODAppUpdate]` so it is testable without Core Data. |
| 4 | `Feather/Views/Odysseus/Settings/ODUpdatesSettingsView.swift` | new UI | Toggle "Check for App Updates" (`ODPrefs.updatesEnabled`), "Check Now" button, last-checked row, count of available updates, and the muted list with per-row `Resume` and `Resume All`. Footer states the matching limitation (§6.5). |
| 5 | `OdysseusTests/ODVersionCompareTests.swift` | original | §6.6 matrix. |
| 6 | `OdysseusTests/ODUpdateMatcherTests.swift` | original | matching, ranking, mute, prefix/suffix, PPQ non-match. |
| 7 | `OdysseusTests/ODSkippedUpdatesManagerTests.swift` | original | persistence and toggle semantics using a throwaway `UserDefaults` suite. |

### 6.3 Files — modify (4)

| # | Path | Change |
|---|---|---|
| 8 | `Feather/Backend/Odysseus/ODPrefs.swift` | Add `updatesEnabled = "Odysseus.updates.enabled"` (Bool), `updatesLastChecked = "Odysseus.updates.lastChecked"` (Double); register defaults `updatesEnabled: true`. No other key changes. |
| 9 | `Feather/Views/Odysseus/Discover/ODCatalogStore.swift` | At the end of `rebuild()`, build `[ODUpdateCandidate]` from `catalog.apps.flatMap(\.offers)` grouped by `offer.app.id` (lowercased — **not** by `ODCatalogApp.id`, which is the source ID joined with the app's unique ID when "Combine Duplicate Apps" is off), pick the highest `currentVersion` per bundle ID, discard entries without `currentDownloadUrl`, and call `ODUpdateChecker.shared.refresh(...)` with a `[ODLocalApp]` snapshot fetched from `Signed`/`Imported` on the main actor. Guarded by `ODPrefs.updatesEnabled`. |
| 10 | `Feather/Views/Odysseus/Library/ODLibraryView.swift` | `_row(_:)`: when `ODUpdateChecker.shared.update(for: app)` is non-nil, show a pill (`v<remoteVersion>` with `arrow.up.circle.fill`) under the version line and add an `Update` item to the context menu that calls `ODSignPipeline.shared.get(update.remoteApp)`. Observe the checker with `@ObservedObject`. No new install path. |
| 11 | `Feather/Views/Odysseus/Settings/ODSettingsView.swift` | One `NavigationLink` row → `ODUpdatesSettingsView()` inside the existing "Sources & Discover" section, with a trailing count when non-zero. |

**Explicitly not modified:** `Feather/Backend/Storage/Storage+Shared.swift` (the `sourceURL` witness is withdrawn), `Feather/FeatherApp.swift` (no launch hook needed — `ODCatalogStore.rebuild()` is already the refresh convergence point), `Feather.xcdatamodeld/**`, `Feather.xcodeproj/project.pbxproj` (both targets use `PBXFileSystemSynchronizedRootGroup`, so new files under `Feather/` and `OdysseusTests/` are picked up automatically; verified `objectVersion = 77`, zero explicit `PBXBuildFile` entries), `license_plist.yml`, `SideSign/`.

### 6.4 Behaviour and data flow

```
source refresh (existing cadence / pull-to-refresh / Settings)
  → SourcesViewModel.fetchSources            (unchanged)
  → ODCatalogStore.rebuild()                 (unchanged catalog build)
  → [new] candidate projection + local snapshot
  → ODUpdateChecker.refresh(...)             (pure match, main actor)
  → @Published updates
  → ODLibraryView pill / Settings screen

Update tap
  → ODUpdateChecker.update(for:) → remoteApp
  → ODSignPipeline.get(remoteApp)            (unchanged download → sign → install,
                                              already handles "no identity" case)
  → existing odysseusDidImportApp path
```

No network request is added. No new credential, entitlement, dependency, or background task is introduced. Two `UserDefaults` keys and one string array are written; nothing is written to Core Data. No migration.

### 6.5 Matching rules (v1, exact)

1. Candidate list is built only from sources the user has added and not hidden, that currently have a downloadable app. Apps with an empty/missing bundle ID or version are dropped.
2. For each local app (`Signed` then `Imported`), the comparison identifier is `identifier` (case-insensitive). If no candidate matches and a prefix/suffix is configured in `ODPrefs`, retry once with the deterministic prefix/suffix stripped (§3.5); the stripped identifier is accepted only if the candidate's name also equals the local name — a **guard**, never a match key.
3. If several candidates match, choose the highest `currentVersion` via `ODVersionCompare.highest`; tie-break by source order in the catalog.
4. Drop the match if the bundle ID is in the mute list, if either version is nil/empty, or if `isNewer(remote, than: local)` is false.
5. Key the result by the local record's UUID.
6. **The app name is never a match key** — not even as a fallback. (Deviation from RyukSign, deliberate — §3.4.)

Documented v1 limitations, surfaced in the Settings footer and in the PR description:

- Apps signed with **PPQ protection** cannot match (random suffix; §3.5).
- Apps signed with a prefix/suffix match only through the strip heuristic; a misconfigured prefix can produce a wrong match and is therefore also checked against the candidate's name before ranking.
- An app sideloaded from outside the user's sources can still match if a source carries the same bundle ID. The pill names the source, the action requires a tap, and the app can be muted.
- No provenance is recorded; uninstalling/reinstalling does not change behaviour, but the "which source did this come from" attribution remains best-effort until Batch 1b.

### 6.6 Tests (all `NOT RUN` in this sandbox)

| File | Cases required |
|---|---|
| `ODVersionCompareTests` | `1.2 > 1.1`; `2.0 > 1.9.9`; `1.0 == 1.0`; `1.1 > 1.0`; `1.0.0 == 1.0`; `1.0 < 1.0.1`; `"1.0b"` → components `[1, 0]`; empty vs non-empty → `false`; both empty → `false`; `highest(["1.2","1.10","2.0"]) == "2.0"` |
| `ODUpdateMatcherTests` | exact identifier match; case-insensitive match; no candidate; equal version → no update; newer version → update; higher of two sources wins; muted bundle ID excluded; prefix strip; suffix strip; prefix+suffix strip; PPQ-suffixed identifier → no match; name-only similarity → **no** match; duplicate local records for one bundle ID both keyed by their own UUID |
| `ODSkippedUpdatesManagerTests` | ignore → persisted; new instance with the same defaults sees it; resume; toggle; `resumeAll`; `isIgnored(nil)` and `isIgnored("")` → `false`; `persisted(in:)` is stable across instances; change notification posted exactly once per mutation |

Tests must use a dedicated `UserDefaults(suiteName:)` and remove it in `tearDown`; they must not touch `UserDefaults.standard`.

### 6.7 Acceptance criteria

1. Every test in §6.6 exists and passes under `xcodebuild test` on macOS/Xcode 26.4 in CI; the existing 16 cases stay green.
2. With "Check for App Updates" off, no matching runs and no Library pill appears.
3. A Library app whose bundle ID matches a source app whose version is newer shows exactly one pill with the remote version and the correct source name.
4. An equal or older remote version shows nothing.
5. Muting an app removes its pill and its count immediately, and survives relaunch.
6. Toggling "Combine Duplicate Apps" does not change which local apps match (guards the `ODCatalogApp.id` pitfall in §6.3 file 9).
7. "Update" runs the existing Get flow and produces no new code path in `ODSignPipeline`.
8. No new `PBXBuildFile` entry is required in `project.pbxproj`.
9. Baseline guarantees intact: `ODZsignOutcome`, OCSP freshness/authorization, Core Data concurrency, and quarantine-on-delete behaviour are untouched (no files in those areas are modified).

### 6.8 Verification statuses after Batch 1 (target)

`SOURCE_VERIFIED` ✓ (both upstreams re-cloned at the pinned commits during this review) · `LICENSE_REVIEWED` ✓ · `IMPLEMENTED` — pending approval · `BUILD_VERIFIED` — pending CI · `AUTOMATED_TESTED` — pending CI · `SIMULATOR_TESTED` / `PHYSICAL_DEVICE_TESTED` — **not planned** · `DOCUMENTED` — this plan + register.

### 6.9 Rollback

Delete the 7 created files, revert the 4 modified files, and clear `Odysseus.updates.*` from `UserDefaults`. No data migration, no Core Data change, no filesystem artefacts, so rollback is a clean revert with no user-visible residue beyond the removed settings rows.

### 6.10 Branch / PR

Work happens on **`arena/b50aa4f2-odysseus`**; PR base **`master`**. No side branch is created (the session branch is fixed and is the only branch Arena will push). Conventional commit: `feat(updates): add app update checker`. PR title: `feat(updates): add app update checker`.

### 6.11 Batch 1b — source provenance (proposed, NOT approved, not part of Batch 1)

Only needed to make attribution exact, to support PPQ-signed apps, and to give "which source did this come from" a real answer. Modelled on upstream Feather (`7078b05`), not RyukSign's name matcher.

Files: `Feather/Backend/Storage/Storage+SourceMetadata.swift` (new), `SourceAppProvenance` struct, `Download.sourceProvenance`, `DownloadManager.startDownload(from:id:sourceProvenance:)`, `FR.handlePackageFile(_:download:sourceProvenance:)`, `AppFileHandler` record write, `SigningHandler(app:)` + `copySourceMetadata`, `Storage+Signed.addSignedAsync(source:)`, `Storage+Shared.AppInfoPresentable.source`, the four `get` call sites that know the source (`ODGetButton`, `DownloadButtonView`, `SourceAppsDetailView`, `ODSignPipeline.get`), plus a new model version and a migration test.

Schema note: adding `AppSourceMetadata` (or `originalIdentifier` on `Signed`/`Imported`) requires a new `.xcdatamodel` version plus `.xccurrentversion` update and a test that opens a store written by the current model. Estimate 10–12 files, medium risk. Requires its own approval.

---

## 7. Decisions needed before implementation

| # | Decision | Recommendation |
|---|---|---|
| D1 | Approve the rescoped Batch 1 (§6, 11 files, no schema change) — or require Batch 1b provenance first and accept the larger, schema-touching batch? | Approve §6. Provenance is a separate risk class and should not gate a read-only feature. |
| D2 | Accept the documented v1 matching limitations (§6.5), specifically: PPQ-signed apps never match, prefix/suffix is a heuristic, a sideloaded app can match a source by bundle ID? | Accept for v1, with the mute list as the escape hatch. If unacceptable, D1 flips to "1b first". |
| D3 | Approve the attribution header text, the `README.md` Credits line, and the register §5 table (§4.2). | Approve as written; it matches the existing `MachOUtils.m` convention. |

On approval, implementation starts at file 1 of §6.2 on `arena/b50aa4f2-odysseus`, in the order listed, with the tests written alongside — not after — the matcher.
