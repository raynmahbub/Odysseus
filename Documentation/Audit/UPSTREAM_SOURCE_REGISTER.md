# Upstream source register

**Audit date:** 2026-10-31 · **Purpose:** identify every project that this app draws on, establish what it is, what it licenses, and what — if anything — may be reused.

## 0. Method and its limits

Each candidate was resolved from the GitHub API (canonical owner/repo, default branch, last push, archived flag, licence, stars) and **shallow-cloned at the current head of its default branch** into `/tmp/up/<name>` for inspection. Commit SHAs below are the exact clones inspected; they are not release tags and will drift.

Verification depth varies by project and is stated per entry:

- **Cloned and read** — file inventory, module layout, licence text read locally.
- **Inventory only** — repository metadata read; code not executed.
- **Unresolved** — no canonical source repository could be established from public evidence.

**No upstream project was built or run.** No conclusion here depends on a README claim about capability; where a README is cited it is marked as a claim.

---

## 1. Register

| # | Project | Canonical repo | Branch | Commit inspected | Licence (verified) | Last push | Stars | Verdict |
|---|---|---|---|---|---|---|---|---|
| U1 | **feather** | `claration/feather` | `main` | `7078b05` | **GPL-3.0** | 2026-10-06 | 4,970 | Direct-ancestor; reuse |
| U2 | **FeatherPlus** | `TomerGamerTV/FeatherPlus` | `main` | not cloned | **GPL-3.0** | 2026-08-13 | 17 | **EXCLUDED** by scope decision |
| U3 | **Ksign** | `Nyasami/Ksign` | `main` | `c14dedc0c9da` | **GPL-3.0** | 2026-10-22 | 724 | Selected donor |
| U4 | **RyukSign** | `faroukbmiled/RyukSign` | `main` | `844466c` | **GPL-3.0** | 2026-09-10 | 110 | Selected donor |
| U5 | **LiveContainer** | `LiveContainer/LiveContainer` | `main` | `9108ae6` | **AGPL-3.0** | 2026-10-17 | 13,630 | Concept only (see §2.6) |
| U6 | **SideStore** | `SideStore/SideStore` | `develop` | `cd26085` | **AGPL-3.0** | 2026-10-27 | 7,179 | Concept only; library already vendored |
| U7 | **FlekDeck** | `flekstore/FlekDeck` | `main` | `6ba96e1` | **AGPL-3.0** | 2026-10-29 | 56 | Concept only |
| U8 | **LiveContainer-FS** | `flekstore/LiveContainer-FS` | `main` | — | **Apache-2.0** | 2025-11-05 | 43 | Possible narrow reuse (§2.7) |
| U9 | **FlekPair** | `flekstore/FlekPair` | `main` | — | **none declared** | 2026-10-28 | 3 | **No licence → must not copy** |
| U10 | **FlareStore** | — | — | — | — | — | — | Unresolved; closed source (§2.9) |
| U11 | **Zeus** | — | — | — | — | — | — | Unresolved; closed source (§2.9) |

Repo-size and code-size observations (clones, excluding `.git`):

| Project | Swift files | Notes |
|---|---|---|
| feather | 149 | Base of Odysseus |
| Ksign | 189 | No test target |
| RyukSign | 275 | 1 test file, widget extension, `Tweaks/` |
| SideStore | 407 | Mature, AGPL, SideBackup + AltStore lineage |
| LiveContainer | 45 Swift + 40 ObjC/C | Container runtime, entitlement-heavy |

Deployment targets (project files): feather **iOS 16.0**, Ksign **16.0**, RyukSign **16.0** (widget 26.0), LiveContainer **15.0–17.5**. Odysseus is **17.0**, so every donor's code is API-compatible in principle; availability must still be checked per file.

---

## 2. Per-project assessment

### 2.1 feather — `claration/feather` (GPL-3.0)

- **What it is:** the original SwiftUI sideloading app (formerly "Feather"). Odysseus descends from it: `FR.swift`, `SigningHandler`, `TweakHandler`, `CertificateFileHandler`, `ServerInstaller`, `Storage+*` and the Core Data model are recognisably the same code, restyled and extended.
- **Structure:** `Feather/{Backend/{AppleID,Certificates,Server,Storage,Observable},Utilities/{Handlers,MachO},Views/{Sources,Library,Settings,Signing}}`.
- **Confirmed delta at `7078b05`:** 11 files present upstream and absent here (`Backend/Observable/UpdateManager.swift`, `Backend/Storage/Storage+SourceMetadata.swift`, `Views/Library/{LibraryCellView,LibraryView,AppIconView}.swift`, `Views/Settings/{SettingsView,SettingsDonationCellView}.swift`, four `Views/TabView/*` files) and ~30 Odysseus-only `OD*` files.
- **Best value:** `UpdateManager` + `Storage+SourceMetadata` (update checking and version provenance), and the tab/settings structure as a reference for the OD redesign.
- **Caveat:** it is the *same lineage*, so importing upstream code re-imports upstream defects (the `try!`/`as!` sites, the unencoded password interpolation, the Core Data password field all exist there too — verified in the clone).
- Since both projects are GPL-3.0, reuse requires only attribution and source availability.

### 2.2 Ksign — `Nyasami/Ksign` (GPL-3.0)

- **What it is:** a recent, feature-dense fork of the Feather lineage (same `FR.swift`, `SigningHandler`, `ServerInstaller+TLS`), pushed 2026-10-22 — the most actively maintained Feather descendant found.
- **Structure that matters:** `Backend/Server/{ServerInstaller+TLS,ServerInstaller+Compute}`, `Utilities/ARDecompression/*`, `Utilities/Handlers/{ArchiveHandler,SigningHandler,TweakHandler,ZsignHandler}`, and a large `Views/Settings/{Installation,Signing Options,Certificates,Archive & Extraction}` tree.
- **Best value:** the *settings taxonomy* and the install-configuration screens; its `SigningHandler`/`ArchiveHandler` are close cousins of the code already here, so diffs are cheap to read.
- **No tests.** Treat every claim as unverified until ported with a test.

### 2.3 RyukSign — `faroukbmiled/RyukSign` (GPL-3.0)

- **What it is:** the broadest fork inspected — 275 Swift files, a widget/Live Activity extension, `Backend/Observable/{AppUpdateChecker,AutoSignManager,BatchJobRunner,EntitlementsManager,TweakManager,InstallQueue,BackupManager,SelfUpdateManager,SigningLog,WebManager,…}`, `Utilities/{MachOEntitlements,MachOReader,InfoPlistPlan,PlistDiff,AppArchiver,IdentityVault,MobileGestalt}`, and `Utilities/Handlers/ArchiveEngine`.
- **Best value, ranked:**
  1. `AppUpdateChecker.swift` — version comparison across sources (adapt, not copy: its venue-builder version comparison is reliable, but it performs `fetchRequest` work on non-main queues and matches apps by name — both must change).
  2. `MachOEntitlements` + `InfoPlistPlan`/`PlistDiff` — the inspection layer Odysseus lacks entirely (`ODY-402`, `ODY-403`).
  3. `BatchJobRunner` + `AutoSignManager` — the right shape for bulk signing (`ODY-301`).
  4. `SigningLog`/`FileLogger`/`StdoutCapture` — structured signing diagnostics (`ODY-302`).
  5. `ManifestService` + `ServerInstaller+Compute` — a manifest server worth diffing against the current one.
- **Caveats:** one test file only; custom `Tweaks/` directory in the tree (unrelated to app behaviour); several screens carry a `PremiumManager` gating concept that is **not** appropriate to port.

### 2.4 SideStore — `SideStore/SideStore` (AGPL-3.0)

- **What it is:** the AltStore fork that introduced on-device signing with anisette. 407 Swift files, `AltStore/`, `Shared/`, `SideBackup/`, a `Makefile`, CI, and an explicit `CERTIFICATE-OF-ORIGIN.md`.
- **Why it matters here:** the `SideSign` library vendored into this repository (8,609 Swift lines) is derived from this family, and the AGPL travels with it.
- **Best value:** not code — *design*: pairing-file acquisition, the anisette server model, certificate lifecycle, and `SideBackup`'s archive format.
- **Blocked:** any code reuse would put Odysseus's network-facing app under AGPL-3.0 §13. See `UPSTREAM_LICENSE_AUDIT.md` §3.

### 2.5 FlekDeck — `flekstore/FlekDeck` (AGPL-3.0)

- A modified LiveContainer (its own `THIRD_PARTY_NOTICES.md` says so) that adds pairing (`IdevicePairing/`), a loopback VPN, and a headless JIT helper (`StikJITHeadless/`).
- **Best value:** only the pairing helper idea (§2.6, G07) and its notices file as a model of how provenance should be recorded.
- **Blocked** for code reuse: AGPL-3.0, and it is a 2026-10-29 push with 56 stars — too volatile to depend on.

### 2.6 LiveContainer — `LiveContainer/LiveContainer` (AGPL-3.0)

- 45 Swift + 40 ObjC/C files, targets iOS 15–17.5, and an `entitlements.xml` containing **exactly 128 `keychain-access-groups`** entries plus HealthKit, increased-memory and app-group entitlements.
- Its README states (claim, not verified): guest app containers **are not sandboxed** from one another, and app extensions cannot be registered.
- **Verdict:** architecturally incompatible. It requires entitlements a sideloaded profile cannot obtain, runs guest code in-process, and depends on `litehook`/`TweakLoader`/`ZSign` at that layer. Nothing in its container runtime is safely portable into a signing app. Its **Mach-O fixup** snippet is the one thing already ported (see §3.1) and that reuse is Apache-2.0, not AGPL — because the file it was taken from carries the Apache-2.0 header.
- Keep as a *concept reference* for `G01–G08` only. Do not merge.

### 2.7 LiveContainer-FS — `flekstore/LiveContainer-FS` (Apache-2.0)

- A small Flek fork; Apache-2.0 makes it the only container-adjacent code that could be mixed into a GPL-3.0 project without changing the licence of the whole app.
- **Not assessed in depth** — no clone was taken because there is no current requirement that would use it. If `G07` is ever pursued, clone and audit it first.

### 2.8 FlekPair — `flekstore/FlekPair` (no licence)

- **No `LICENSE` file and no licence field in the repository metadata.** Default copyright applies: **no permission to copy, modify, or redistribute.** Do not open, port, or paste anything from this repo.

### 2.9 FlareStore and Zeus — unresolved, closed source

- **FlareStore:** GitHub repository search returns no project matching the product; results are unrelated packages and repackaged builds. There is no canonical source to inspect, license, or reuse.
- **Zeus:** a product site (`getzeus.app`) exists; `gh search repos` returns nothing authoritative.
- **Therefore:** both are recorded as **concept references only**. No claim of code reuse may be made anywhere in this repository, and no text may imply derivation.

### 2.10 FeatherPlus — excluded

- A small fork of the Feather lineage (17 stars, last push 2026-08-13, GPL-3.0). **Scope decision: excluded.** Listed here only so future readers know it was considered and deliberately dropped, not overlooked.

---

## 3. What is actually already reused here (provenance audit)

| Source | Location in Odysseus | Evidence of provenance | Obligation |
|---|---|---|---|
| feather (GPL-3.0) | the bulk of `Feather/` | same file names, structures and code as the clone; shared lineage | GPL-3.0 notice retained (`LICENSE`); modifications disclosed in source |
| LiveContainer `LCPatchMachOFixupARM64eSlice` (Apache-2.0) | `Feather/Utilities/MachO/MachOUtils.m` | file header cites the exact upstream commit `3a029b6b…` and states Apache-2.0 | retain the comment; Apache-2.0 §4 notices; combined work stays GPL-3.0 |
| AltSourceKit (MIT, © 2025 CLARATION) | `AltSourceKit/` | package `LICENSE` present | MIT notice retained |
| NimbleKit (MIT, © 2025 CLARATION) | `NimbleKit/` | package `LICENSE` present | MIT notice retained |
| SideSign (AGPL-3.0) | `SideSign/` | `SideSign/LICENSE` is the AGPL text | AGPL obligations apply to the combined binary (see licence audit §3) |
| ElleKit (BSD-3-Clause) | `LICENSE_ELLEKIT`, bundled `ellekit.deb` | licence file present | retain copyright + disclaimer |
| Zsign (MIT) | `Zsign/` submodule (not checked out here) | declared in `license_plist.yml` | retain MIT notice |
| idevice / IDeviceKitten (MIT) | `IDeviceKitten/` submodule | declared in `license_plist.yml` | retain MIT notice |

**Two provenance defects found in the current repo:**

1. `license_plist.yml` references `LICENSE_EllEKIT` (case differs from the actual `LICENSE_ELLEKIT`). On a case-sensitive filesystem (some CI containers, external contributors on Linux) the ElleKit licence silently drops out of the generated acknowledgements.
2. `license_plist.yml` references `Zsign/LICENSE_LC` for LiveContainer's Zsign-derived code — resolvable only when the submodule is populated, and even then its presence has not been verified in this environment. **For review** before any distribution.

---

## 4. Selection conclusion

| Need | Best source | Mode |
|---|---|---|
| Update checking | feather `UpdateManager` + RyukSign `AppUpdateChecker` | **adapt** (design + version comparison) |
| Entitlements / plist editing | RyukSign `MachOEntitlements`, `InfoPlistPlan`, `PlistDiff` | **adapt** |
| Bulk signing | RyukSign `BatchJobRunner` + `AutoSignManager` | **adapt** |
| Signing diagnostics | RyukSign `SigningLog` | **adapt** |
| Settings taxonomy / install config UI | Ksign | **adapt** |
| Backup format | RyukSign `BackupManager`/`BackupCrypto` or SideStore `SideBackup` | **adapt one**, do not mix (licence) |
| Container execution | LiveContainer / FlekDeck | **impossible** in this architecture |
| Everything already vendored | — | **direct reuse**, keep notices |

No project in this register can be lifted wholesale: three of the most attractive (LiveContainer, SideStore, FlekDeck) are AGPL-3.0 and would relicense the application; the rest are GPL-3.0 siblings whose defects are shared with this codebase.
