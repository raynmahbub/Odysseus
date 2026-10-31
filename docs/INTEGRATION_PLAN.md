# Integration plan

**Audit date:** 2026-10-31 (UTC) · **Revision:** `c2040b0` (byte-identical to the audited `2a54e3b` outside `docs/`)
**Working branch:** `arena/b50aa4f2-odysseus` (== `master`); all work lands there and is proposed to `master` as one PR.
**Status:** proposal — **no production code changed yet.** Batch 1 was **rescoped** on 2026-10-31 after the data-model check in [`BATCH1_READINESS_REVIEW.md`](BATCH1_READINESS_REVIEW.md) §3; it is awaiting the three decisions in that document's §7.

Batches are ordered by risk and dependency. Each is independently reviewable and revertable. Feature IDs reference `SOURCE_INTEGRATION_MATRIX.md`.

---

## Batch index

| Batch | Feature(s) | IDs | Size | Risk |
|---|---|---|---|---|
| 0 | Audit + docs + foundation checks | — | docs | low |
| **1** | **App update checker (core + UI)** — rescoped, no schema change | **R-UPD-01 / F-UPD-01** | **11 files** | **low** |
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

# Batch 1 — App update checker (re-proposed)

**Status: proposed, not approved.** The exact file-by-file plan, behaviour, matching rules, tests, acceptance criteria, and rollback are in [`BATCH1_READINESS_REVIEW.md`](BATCH1_READINESS_REVIEW.md) §6. That section is the authoritative plan; this page does not restate it, to avoid two versions drifting apart.

## What changed from the first draft

| Change | Reason |
|---|---|
| Dropped the `sourceURL` addition to `AppInfoPresentable` (`Storage+Shared.swift` is no longer modified) | `Signed.source` is never written and `Imported.source` is never populated by the import path, so the witness would always return `nil` and the checker would silently match nothing. See review §3.2. |
| Dropped the `FeatherApp.swift` launch hook | `ODCatalogStore.rebuild()` is already the refresh convergence point and now feeds the checker. |
| Added `ODCatalogStore.swift` and `ODPrefs.swift` to the modified list | Consume the existing catalog instead of a second `NBFetchService` fetch path; add namespaced preference keys. |
| No name-based matching (deviation from RyukSign) | RyukSign matches by display name, which can offer an update from an unrelated app. Review §3.4. |
| Core Data values are snapshotted before matching | RyukSign reads `FetchedResults` inside a detached task — the exact bug class fixed in the security remediation. |
| Three test files instead of one | One file per unit under test, matching the existing `OdysseusTests` layout. |
| Deterministic prefix/suffix stripping added | Apps signed with a bundle-ID prefix/suffix would otherwise never match. PPQ cannot be reversed and is documented as unsupported in v1. |
| Explicit follow-up: Batch 1b (provenance, schema change) | Proper attribution needs `AppSourceMetadata` (Feather) or `originalIdentifier` (RyukSign); that is a migration-bearing change and needs its own approval. |

## Summary

- **Objective:** tell the user when a Library app has a newer version in one of their sources; per-app mute; Settings screen; manual "Check Now".
- **Files:** 7 created (`ODVersionCompare`, `ODSkippedUpdatesManager`, `ODUpdateChecker`, `ODUpdatesSettingsView`, 3 test files), 4 modified (`ODPrefs`, `ODCatalogStore`, `ODLibraryView`, `ODSettingsView`).
- **No** schema change, no new dependency, no new entitlement, no new network path, no new install path.
- **Verification target:** `BUILD_VERIFIED` + `AUTOMATED_TESTED` via CI only; simulator/device testing not planned.

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
