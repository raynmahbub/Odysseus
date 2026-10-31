# Odysseus architecture audit

**Audit date:** 2026-10-31 · **Revision:** `6ee21d6` · **Companion documents:** baseline (§4 module map), feature matrix, bug audit.

## 1. Judgement in one paragraph

Odysseus is a **single-module SwiftUI application** built on the Feather codebase with a re-skinned information architecture and one genuinely new subsystem (OCSP revocation). Its pipeline — *acquire → import → inspect → sign → package → install* — is real and complete, and the persistence layer shows deliberate effort at consistency (snapshots, background contexts, delete-with-restore). What it does **not** have is any architectural boundary: views orchestrate signing, a static facade (`FR`) hides the pipeline, twelve global singletons carry state, the Core Data model is unversioned, and business logic lives under `Views/`. Those are the reasons the codebase is hard to test, and they are why the testing strategy has to be written before the next feature.

The recommendation is **not** a rewrite. It is a strangler migration: introduce four seams (`SigningService`, `InstallService`, `SourceService`, `DownloadService`), move the three view-resident stores into `Backend/`, and version the model — each step independent and shippable.

---

## 2. Actual structure

One target (`Feather`), one Core Data model, no framework targets. The folder layout *looks* layered but the dependency direction is not enforced anywhere — `Views/` imports `Backend/`, `Backend/` imports `Utilities/`, and `Utilities/` imports `SideSign` and the submodules directly.

```
FeatherApp + AppDelegate
   │  (URL schemes, background tasks, lifecycle)
   ▼
ODRootView ──► Discover ──► ODCatalogStore ──► SourcesViewModel ──► Storage+Sources
   │              │                                                     │
   │              └──► ODSignPipeline.get() ──► DownloadManager ────────┘
   │                          │
   ├──► Library (ODLibraryView) ──► ODSignPipeline.signAndInstall()
   │                                     │
   │                                     ├──► FR.handlePackageFile()  ← static facade
   │                                     │        └── AppFileHandler → CertificateFileHandler
   │                                     │             → SigningHandler → TweakHandler → ZsignHandler
   │                                     │                   └──► SideSign (AGPL) / Zsign (submodule)
   │                                     └──► ODSignPipeline.install()
   │                                              └──► ServerInstaller (+TLS) ──► Vapor
   │
   ├──► Settings (ODSettingsView) ──► ODPrefs / OptionsManager / ODDiagnosticsView
   └──► Apple ID (ODAppleIDView) ──► ODAppleIDManager ──► SideSign + ODKeychain
```

### 2.1 Where the responsibilities actually live

| Responsibility | Should be | Is |
|---|---|---|
| Pipeline orchestration | Backend service | `Backend/Odysseus/ODSignPipeline.swift` (440 lines) — correct place, but exposed as a singleton `ObservableObject` that views mutate |
| Catalog / storefront state | Backend | `Views/Odysseus/Discover/ODCatalogStore.swift` (81 lines) — under `Views/`, singleton, owns `UserDefaults` observation |
| Source fetching | Backend | `Views/Sources/SourcesViewModel.swift` — under `Views/` |
| Signing orchestration | Backend service | split between `ODSignPipeline`, static `FR`, and `SigningHandler`; three entry points |
| Library queries | Repository | `Storage` singleton + per-view `@FetchRequest`; no repository layer |
| Deep links | Router | `FeatherApp._handleURL` reaches into singletons directly |

### 2.2 Coupling facts

- **13 `static let shared` declarations across 12 files**: `Storage`, `ODSignPipeline`, `ODAppleIDManager` (two), `ODCertificateStatusStore`, `DownloadManager`, `OptionsManager`, `SourceFetchErrorToastCenter`, `BackgroundAudioManager`, `BackgroundTaskManager`, `SourcesViewModel` and `ODCatalogStore` (both under `Views/`), and `FRAppIconView`.
- **`FR` is a static namespace** (`FR.swift`, 224 lines, 7 responsibilities): package handling, signing, certificate handling, password checking, pairing import, source import, export + URL construction. It has no protocol, so nothing that calls it can be faked.
- **`ODSignPipeline` is both service and view model**: it publishes `phases`, `failures`, `importProgress`, and it also downloads, imports, signs and installs.
- **Views own business decisions**: `ODLibraryView` (360 lines) builds `Options`, decides identity, and calls `signAndInstall`; `ODGetButton` decides to download or re-import a previously downloaded app.
- **Legacy and new trees coexist**: `Views/Library/*`, `Views/Settings/SettingsView.swift`, `Views/TabView/*` sit beside `Views/Odysseus/*`. Eleven upstream files were replaced rather than deleted, and 51 type declarations have no reference outside their own file (dead-code scan; false positives manually excluded — see bug audit BUG-010).

---

## 3. Data flows (verified)

### 3.1 Acquire → sign → install (`ODSignPipeline`)

1. `get(_:)` resolves the `ASRepository.App`, possibly through the bundle-ID override, and creates a `Download` in `DownloadManager`.
2. `DownloadManager` writes to `FeatherDownloads/<uuid>/<name>.ipa`, with a silent-audio keepalive and a background task per download.
3. `handlePachageFile` → `FR.handlePackageFile` → `AppFileHandler.extract()` (unzip with **no** entry/size limits) → `addToDatabase` on a background context → posts a notification.
4. `ODSignPipeline._didImport` resolves the object ID on the view context, marks the phase `.signing`, and calls `signAndInstall`.
5. `signAndInstall` checks defaults (certificate present? none → alert), runs `_revocationGate` (OCSP), then `sign()` → `SigningHandler` (Metadata plist edits, dylib injection, icon, bundle ID, extension handling, Watch removal) → `ZsignHandler` (entitlements + provision + `Zsign.sign`) → presence check.
6. `install()` picks a transport: semi-local server, fully-local TLS, or pairing/IDevice.
7. Success → `.done`; failure → `failures[uuid]` + alert.

**Seam quality:** steps 3–5 are real and shared by the import path too; step 6 is a `switch` on `ServerInstaller.mode`. This is the best part of the codebase and the natural place to insert protocols.

### 3.2 Source refresh

`ODCatalogStore` observes `UserDefaults.didChangeNotification` with a debounce, calls `SourcesViewModel.fetchSources`, which (`SourcesViewModel.swift:34`) **returns early if `!isFinished`**, then fans out to every source with `withTaskGroup`, merging into `sources: [String: ASRepository]` — **memory only**. `ODCatalog` re-derives featured/categories/duplicates each `load()`.

Consequences: no offline storefront, no per-source status, duplicate source detection by identifier only, and a refresh can be silently dropped (BUG-011).

### 3.3 Certificate lifecycle

Import (`CertificateFileHandler.copy()` → `Documents/Feather/Certificates/<UUID>/{cert.p12,prov.mobileprovision}`) → `Storage+Certificate.addCertificate` (stores `password` in Core Data) → status checks (`ODCertificateStatusStore` → `ODOCSPChecker`) → UI pills (`ODExpiryPill`, `ODOCSPPill`). Export is `FR.exportCertificateAndOpenUrl` (base64 + raw password in a URL).

The OCSP path is the only place with a clear module boundary (`ODOCSPChecker` depends on `ODDER`/`ODX509`/`ODOCSPCore`, all pure and testable) — and it is the only place with tests.

### 3.4 Persistence

- **Core Data**: one unversioned `.xcdatamodeld`; entities `Signed`, `Imported`, `Downloaded`, `CertificatePair`, `AltSource`, `AppArch`. Writes go through `Storage` with `perform`/`performBackgroundTask`; `Signed`/`Imported` share `_deleteRecord` with a quarantine directory and restore-on-failure.
- **UserDefaults**: `ODPrefs` (many keys), `ODDownloadOrigin` (a growing UUID list), per-app signed metadata in `ODAppleIDSignedApps`.
- **Keychain**: `ODKeychain` for Apple ID email/password; **certificate passwords are not in the keychain**.
- **Files**: `Documents/Feather/{Certificates,Archive}`, `Library/…/FeatherDownloads/`, `tmp/FeatherInstall_<uuid>/`.

There is no schema version, no migration plan, and no `NSPersistentStoreDescription` protection class. Adding a field to `CertificatePair` (roadmap ODY-102) therefore requires a lightweight-migration review.

---

## 4. Concurrency model

| Mechanism | Usage | Assessment |
|---|---|---|
| `@MainActor` | views, `ODSignPipeline`, `ArchiveHandler` | correct for UI |
| `Task.detached` | 17 sites (file copying, extraction, signing) | acceptable but unstructured; cancellation is not propagated to Zsign |
| `TaskGroup` | source fan-out | correct |
| `DispatchQueue` | ObjC `MachOUtils`, `AR` decompression | bounded, fine |
| Background Core Data contexts | import/download bookkeeping | correct pattern, snapshot discipline is good |
| `BGTaskScheduler` | registered per download id at runtime (`BackgroundTaskManager.swift:27`) | **registration after launch is not supported** for identifiers not in `BGTaskSchedulerPermittedIdentifiers` (BUG-004) |
| Silent audio | `BackgroundAudioManager.start()` → `_engine.attach(silence)` each call | keeps the app alive; attaches without detaching (BUG-009) |

No `DispatchQueue.main.sync` anywhere (verified). Two `@unchecked Sendable` (`DownloadManager`, `AppFileHandler`) are documented and narrow.

---

## 5. Telemetry and errors

`Logger++` wraps `OSLog`; `ODDiagnosticsView` exports the current process's log via `OSLogStore`. There are **no** `privacy:` annotations in the codebase (0 occurrences), so dynamic strings rely on OSLog's default redaction. Three `print(` calls remain (`DownloadManager.swift:217`, `BackgroundAudioManager.swift:37`, `BackgroundTaskManager.swift:46`) — one of them is the *only* signal for a failed import (BUG-002/BUG-003).

---

## 6. Assessment

### 6.1 Strengths (do not regress)

1. **One pipeline, three entry points** — download, URL, and library all converge on `ODSignPipeline`; behaviour cannot diverge per entry point except where explicitly coded.
2. **Snapshot discipline** — `ODSignAppSnapshot`, `AppArchiveSnapshot`, and `_didImport(objectID:)` avoid passing `NSManagedObject` across queues. This is a genuine, tested improvement over upstream.
3. **Quarantine delete with restore** — `Storage+Shared._deleteRecord` moves files aside, deletes the record, restores on failure; covered by a unit test.
4. **OCSP as a real module** — parsing, signature verification, responder authorisation, Apple trust anchoring, freshness, caching, three policies. Pure functions, testable, tested.
5. **Local TLS identity is user-owned** — generated per device, `0o700`/`0o600`, `completeFileProtection`, and the server refuses to start without it (no silent plaintext downgrade). Better than the upstream pattern.
6. **Apple ID secrets in the keychain**, not in Core Data — correct choice, even though return codes are ignored.
7. **CI that tests and verifies the artefact** — `xcodebuild test` + `make iphoneos` + `scripts/verify_ipa.sh` on every push.

### 6.2 Weaknesses (ranked by cost to future work)

| # | Weakness | Evidence | Cost |
|---|---|---|---|
| W1 | No service protocols; `FR` is static | `FR.swift`, all call sites | cannot unit-test any pipeline stage |
| W2 | Views orchestrate business logic | `ODLibraryView.swift`, `ODGetButton.swift`, `ODInstallSheet.swift` | feature work keeps adding logic to views |
| W3 | Store/catalog under `Views/`, singleton | `ODCatalogStore.swift` | storefront logic untestable and invisible to back end |
| W4 | Two parallel UI trees | `Views/Library/*` vs `Views/Odysseus/Library/*` | every UI fix risks drift; 51 unreferenced types |
| W5 | Unversioned Core Data model | `Feather.xcdatamodeld` | any schema change is risky |
| W6 | No offline source cache | `SourcesViewModel.sources` | storefront is empty without network |
| W7 | Secrets in Core Data + Documents | `Storage+Certificate.swift:30`, `CertificateFileHandler.copy()` | security debt that blocks release |
| W8 | Error paths silent | `DownloadManager.swift:217`, `Storage+Certificate.swift:48` | failures look like freezes |
| W9 | No dependency provenance | no root `Package.resolved`; branch-pinned SideSign deps | unreproducible builds, licence drift |
| W10 | Private API in diagnostics | `MobileGestalt.swift` (`dlopen` + `dlsym`) | App Review risk; trivially avoidable |

---

## 7. Target architecture (incremental, no rewrite)

The goal is **testability and a stable install pipeline**, not microservices.

```
Feather (single target, folders as boundaries)
├── App/            lifecycle, router (deep links → typed commands)
├── Domain/         pure models + protocols: SigningService, InstallService,
│                   SourceService, DownloadService, CertificateStore
├── Features/       Discover, Library, Signing, AppleID, Settings, Install
│                   (views only; receive view models)
└── Infrastructure/ Zsign, SideSign, Vapor server, Core Data, Keychain, Files
```

**Dependency rules (enforced by review, then by a CI grep):**

1. `Features` may import `Domain` only.
2. `Domain` imports nothing from `Infrastructure` — it declares protocols; implementations are injected at the app root.
3. `Infrastructure` may import third-party packages and ObjC; nothing else imports it directly.
4. No `static let shared` outside `App/`.
5. No file under `Features/` may call `FR.*`, `Zsign.*`, or `ServerInstaller.*` directly.

**Seam definitions (signatures only, to settle scope):**

```swift
protocol SigningService: Sendable {
    func inspect(_ ipa: URL) async throws -> AppBundleDescriptor
    func sign(_ descriptor: AppBundleDescriptor, with: SigningConfiguration) async throws -> SignedArtifact
}
protocol InstallService: Sendable {
    func install(_ artifact: SignedArtifact, via: InstallTransport) async throws
}
protocol SourceService: Sendable {
    func refresh() async -> [SourceSnapshot]          // last-good cache included
    func add(_ url: URL) async throws -> SourceSnapshot
}
protocol DownloadService: Sendable {
    func download(_ request: DownloadRequest, progress: @Sendable (Double) -> Void) async throws -> URL
}
```

`ODSignPipeline` then becomes a thin coordinator that composes these four and publishes phases — keeping its current UI contract.

### 7.1 Migration sequence (each step shippable)

| Step | Action | Risk | Unlocks |
|---|---|---|---|
| M1 | Wrap `FR` behind `SigningService` + `InstallService` with the current implementations; no behaviour change | low | pipeline tests |
| M2 | Move `ODCatalogStore` and `SourcesViewModel` to `Backend/Sources/` as `SourceService` + add a disk cache | medium | offline storefront, source health |
| M3 | Introduce `CertificateStore` protocol over `Storage+Certificate`; move p12 password to keychain | medium | security fixes, tests |
| M4 | Delete the unreferenced legacy view tree after a manual reference audit | medium | removes drift |
| M5 | Version the Core Data model and add a store-description protection class | medium | future schema work |

Do **not** attempt a full module extraction (separate frameworks) in this cycle: build times, `PBXFileSystemSynchronizedRootGroup` benefits, and CI complexity outweigh the gain until the seams exist.

---

## 8. Why the container-class features do not fit

LiveContainer-class execution needs (a) entitlements a sideloaded profile cannot obtain — upstream's `entitlements.xml` contains exactly 128 keychain access groups and HealthKit/memory entitlements; (b) guest code loaded into the host process, which contradicts the quarantine/extraction model; (c) `litehook`/`TweakLoader` at runtime. It also documents that guest containers are **not** isolated from one another. Adding it would not be a feature, it would be a second product with different security properties. Ported pieces must stay limited to signing-time Mach-O fixups, which are already present (`MachOUtils.m`, Apache-2.0).

---

## 9. Architecture risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Adding features on top of view-resident logic increases regression risk | high | high | M1 before ODY-101 |
| Schema change for update tracking breaks the store | medium | high | M5 before ODY-101 ships |
| Legacy tree drift produces "fixed in one screen only" bugs | high | medium | M4 |
| Silent download/import failures make device QA ineffective | high | medium | BUG-002/003 fixes in Phase 0 |
| Dependency drift breaks CI without a code change | medium | medium | pin + `Package.resolved` (L-02) |
