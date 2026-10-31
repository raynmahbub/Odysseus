# Odysseus architecture

**Audit date:** 2026-10-31 (UTC) · **Revision:** `c2040b0` (byte-identical to the audited `2a54e3b` outside `docs/`)
**Scope:** document the *verified* current architecture and a *proposed* target architecture for integrating upstream features. Distinguishes facts from proposals.

---

## 1. Current architecture (verified)

Odysseus is a **single iOS application target** (internally `Feather`, product `Odysseus`) built from a modified Feather snapshot plus an Odysseus layer. One SwiftUI app, one Core Data model, one process. There is no separate framework/package boundary between "Feather" and "Odysseus" code — they live in the same module and share types.

```
FeatherApp (@main) ─── AppDelegate
   │
   ├── Storage.shared  (Core Data "Feather" model; @MainActor viewContext + background contexts)
   ├── ODRootView ── TabView
   │     ├── ODDiscoverView   ── ODCatalogStore ── ODCatalog ── AltSourceKit sources
   │     ├── SourcesView      ── SourcesViewModel ── AltSourceKit / NBFetchService
   │     ├── ODLibraryView    ── Signed/Imported/Certificates (Core Data fetch requests)
   │     └── ODSettingsView   ── ODPrefs / OptionsManager / ODAppleIDView / ODDiagnosticsView
   │
   ├── ODSignPipeline.shared  (the "sign this app / get this app" seam)
   │     ├── identity: ODSigningIdentity { .certificate(CertificatePair?), .appleID }
   │     ├── revocation gate (ODOCSPChecker / ODCertificateStatusStore / ODPrefs.revokedAction)
   │     ├── FR.signPackageFile → SigningHandler → ZsignHandler → Zsign
   │     │        └── TweakHandler (injection), SigningHandler plist/Mach-O mods
   │     └── install(signedUUID) → ODInstallSheet
   │
   ├── Installation
   │     ├── Semi-local: ServerInstaller (Vapor) + external plist server + webview redirect
   │     ├── Fully-local: ServerInstaller + ODLocalServerTLS (user-owned TLS identity)
   │     └── Pairing: HeartbeatManager + IDevice AFC/installd (LocalDevVPN + pairing file)
   │
   └── Apple ID: ODAppleIDManager + ODKeychain + vendored SideSign (AGPL-3.0)
```

### Verified module boundaries

| Boundary | Evidence |
|---|---|
| Signing is a single pipeline | `ODSignPipeline.sign(...)` is the only path used by Discover-Get, direct signing, and Apple ID; `FR.signPackageFile` wraps `SigningHandler`. |
| Identity selection is a small enum | `ODSigningIdentity { .certificate, .appleID }` in `ODSignPipeline.swift`. |
| Persistence is Core Data + filesystem | `Storage` (Core Data `Feather` model) + `FileManager` Documents trees (`Signed/`, `Unsigned/`, `Certificates/`, `Archives/`). |
| Revocation is a gate in front of signing | `_revocationGate` + `_freshResult` in `ODSignPipeline`. |
| Installation is two/three transports behind `ODInstallSheet` | `ServerInstaller`, `ODLocalServerTLS`, IDevice pairing. |
| Apple ID signing is isolated behind `ODAppleIDManager` + SideSign | `prepareSigning(...)` returns `ODAppleIDSigningMaterial`; the pipeline consumes it as an `ODSigningOverride`. |

### Data flow (Get, one tap)

```
Discover Get → DownloadManager.startDownload → FR.handlePackageFile
   → AppFileHandler: copy → extract → move → addToDatabase (Imported record)
   → Notification odysseusDidImportApp → ODSignPipeline._didImport
   → signAndInstall → sign()
        → identity resolution (cert / Apple ID)
        → _revocationGate (OCSP)
        → bundle-ID adjust (ODPrefs)
        → FR.signPackageFile → SigningHandler: copy → modify (plist/icon/tweaks/Mach-O) → ZsignHandler.sign → move → addToDatabase (Signed record)
   → ODSignPipeline.install → ODInstallSheet → ServerInstaller / pairing
```

### Error handling (verified)

- `ODSignError` (`noCertificate`, `revokedBlocked`, `cancelled`, `importFailed`) + `SigningFileHandlerError` + `StorageRecordError` + `StorageDeleteError` + `ODAppleIDError` + `ODOCSPResult.couldntCheck`.
- Signing failures propagate through `withCheckedThrowingContinuation`; `ODZsignOutcome.validate` requires the Zsign Boolean return, callback, callback success, and a `checkSigned` presence check.
- Core Data: `waitUntilStoreLoaded()`; load failure → `storeLoadError` surfaced in UI; deletes quarantine files and restore on failure.
- Apple ID temp material removed via `defer`.
- Gaps: `ServerInstaller` startup errors captured via `make(...)`; some `try?` remain in server setup (documented in BASELINE_AUDIT §4.9).

---

## 2. Proposed target architecture

**Goal:** adopt upstream features with clear boundaries and without combining overlapping signing engines or persistence systems.

```
Odysseus (single app target; module boundaries are logical, enforced by convention + tests)
│
├── Discovery & Sources
│    ├── ODCatalogStore / ODCatalog            (unchanged)
│    ├── Sources (AltSourceKit)                (unchanged)
│    └── [NEW] AppUpdateChecker                (R-UPD-01) ── compares Library vs sources
│
├── App Library
│    ├── Signed / Imported / Certificates      (unchanged Core Data)
│    ├── [NEW] TweakLibrary + TweakManager     (R-TWEAKMGR-01) ── managed tweak store
│    ├── [NEW] StorageManager                  (R-STORAGE-01)
│    └── [NEW] FileManager (Files)             (K-FILES-01) ── browse/edit local files
│
├── Signing
│    ├── ODSignPipeline (unchanged seam)
│    │    ├── IdentityProvider: CertificateIdentity | AppleIDIdentity
│    │    ├── RevocationGate (OCSP)            (unchanged)
│    │    ├── OptionsApplier (plist/entitlements/icon/tweaks)
│    │    │     ├── [NEW] EntitlementsEditor   (R-ENT-01)
│    │    │     └── [NEW] InfoPlistEditor      (R-PLIST-01)
│    │    ├── ZsignAdapter (unchanged)
│    │    └── [NEW] BatchSignEngine            (R-BATCH-01) ── queues multiple sign jobs
│    └── [NEW] TweakInjector (shared by single + batch)
│
├── Installation
│    ├── ServerInstaller (Vapor) + ODLocalServerTLS   (unchanged)
│    ├── PairingInstaller (IDevice)                   (unchanged)
│    └── [NEW] WebTransferServer (HTTP + WebDAV)      (R-WEB-01/02/03)
│
├── Apple ID
│    └── ODAppleIDManager + SideSign (unchanged)
│
├── Diagnostics
│    └── [NEW] unified Logger/LogStore            (R-LOG-01) — OSLog + file + history
│
└── [SEPARATE WORKSTREAM, BLOCKED] AppContainer (LiveContainer-derived)
        LiveContainer host + LiveProcess + entitlements + keychain groups
```

### Principles

1. **One signing pipeline.** New signing capabilities (batch, entitlements editor, plist editor) plug into `ODSignPipeline`/`SigningHandler`, not parallel UI flows.
2. **One tweak subsystem.** A managed `TweakLibrary` feeds both per-sign injection and batch signing; no duplicate injection engines.
3. **One persistence model.** New features extend the existing Core Data model or use clearly-scoped UserDefaults/keychain; do not introduce a second database.
4. **One log subsystem.** Consolidate OSLog, file logs, and signing logs.
5. **Install transports stay adapters.** Server / pairing / web-transfer are alternative `Installer` adapters behind `ODInstallSheet`.
6. **App container is a separate process/architecture**, gated (see §6).

---

## 3. Dependency direction

```
Views  →  Backend (pipelines, stores, managers)  →  Utilities (handlers, FR)  →  External (Zsign, SideSign, AltSourceKit, IDevice, Vapor)
   ↑                                                                              ↑
ODPrefs/Options  (settings)                                        Core Data / FileManager / Keychain (Storage)
```

- Views depend on backend managers; backend depends on utilities; utilities depend on external engines.
- `ODSignPipeline` is the convergence point for Discover, Library, and direct signing.
- Upstream integrations should land in `Backend/` + `Utilities/` (logic) and `Views/` (UI), matching existing conventions.

## 4. Security boundaries and sensitive data

| Boundary | Current handling | Proposed |
|---|---|---|
| Signing identity material | p12 + password in `ODSigningOverride` (Sendable snapshot); password never logged; p12 in protected Documents/temp | Keep; extend to batch engine; ensure no identity material crosses into logs or crash reports |
| Apple ID material | temp UUID dir `0700`, `defer` cleanup, 24h stale cleanup | Keep |
| TLS private key (Fully Local) | user-owned, protected storage, validated at activation + startup; no bundled key | Keep |
| Keychain | `ODKeychain` for Apple ID secrets | Keep; route new secrets through it |
| OCSP decisions | `isFresh` requires `signatureVerified` + validity window | Keep; add tests for live-response shapes |
| Source feeds | AltSourceKit parsing; default sources auto-installed | Re-evaluate default sources; validate/sanitize feeds |
| Web transfer server (new) | — | Must bind to loopback only, require auth, never expose filesystem outside app sandbox |
| WebView downloader (new, K-WEBDL-01) | — | Restrict schemes; never follow `itms-services`/`odysseus` redirects unchecked |
| App container (blocked) | — | Guest containers are not sandboxed upstream; requires an explicit security review before any adoption |

## 5. Persistence and migration implications

- Core Data model `Feather` currently has entities for `Signed`, `Imported`, `CertificatePair`, `AltSource` (and the Odysseus additions). New features that need persistence:
  - **Update checker:** Batch 1 (re-proposed) persists **nothing** in Core Data — it compares against the in-memory `ODCatalogStore` catalog and keeps only a UserDefaults mute list, so it needs no model change. Provenance (`AppSourceMetadata` entity, Feather upstream) is deferred to Batch 1b because it requires a new model version plus a migration test. See `BATCH1_READINESS_REVIEW.md` §3.7 and §6.11.
  - **Tweak library:** a new entity (`Tweak`/`TweakFile`) or a folder-based store under Documents. RyukSign uses folder + models; decide one.
  - **Batch queue:** in-memory + persisted job records if interruption recovery is required.
- Migration: adding entities is additive (no breaking migration) as long as the model version is bumped and lightweight migration is enabled (`NSPersistentContainer` default). **Do not** reuse the destructive recovery path removed in the remediation.
- Filesystem: new stores under `Documents/` (`Tweaks/`, `WebTransfer/`); keep quarantine/restore semantics for deletions.

## 6. LiveContainer-style app container — feasibility & security workstream

**Status: BLOCKED / INVESTIGATE.** Not a signing feature.

- Requires a second executable (`LiveProcess`) and multiple app extensions, plus entitlements beyond `get-task-allow` (`com.apple.developer.kernel.in increased-memory-limit`, 128 keychain groups, app groups, healthkit).
- Guest containers are **not sandboxed** upstream (documented limitation) — one guest can read another's data. This is a material security boundary change.
- Architecture is in-process guest execution (patch Mach-O, `dlopen`, jump to entry), incompatible with Odysseus's "sign then install normally" model.
- **Gate:** before any adoption, produce a security review + a standalone prototype and get explicit approval. Do not combine with the signing pipeline.

## 7. Alternatives, trade-offs, unresolved decisions

| Decision | Options | Trade-off / recommendation |
|---|---|---|
| Update checker source | Feather `UpdateManager` vs RyukSign `AppUpdateChecker` | **Resolved:** take RyukSign's skip list, reject its matcher (name matching, `originalIdentifier`, off-main `FetchedResults`), and drive both from `ODCatalogStore`. Feather's `AppSourceMetadata` design is Batch 1b. See `BATCH1_READINESS_REVIEW.md` §3. |
| Tweak management | RyukSign `TweakManager` vs keep per-sign only | RyukSign's is a distinct, high-value feature; adopt with an OD-native library layout. |
| Backup | RyukSign `BackupManager` vs SideStore `SideBackup` | Pick one; RyukSign's is self-contained; SideBackup implies SideStore refresh. |
| Web transfer | RyukSign HTTP/WebDAV vs custom | Adopt RyukSign's; reuses Vapor. |
| Live Activities | RyukSign widget extension | Requires a new app-extension target; adopt after batch signing (shares download manager). |
| App container | Full LiveContainer/FlekDeck vs nothing | Blocked pending security review; do not start. |
| SideStore refresh | Full SideStore vs SideSign-only (current) | Large, orthogonal transport; keep as separate INVESTIGATE workstream. |
| FeatherPlus / Zeus / FlareStore | Unknown | Cannot plan without repository identities. |

## 8. Upstream integration points (summary)

- **Feather upstream:** `Backend/Observable/UpdateManager.swift`, `Backend/Storage/Storage+SourceMetadata.swift` → update checker.
- **Ksign:** `Views/Files/*`, `Views/Downloader/*`, `Views/Library/Frameworks&Dylibs/*`, `Views/Signing/BulkSigningView.swift`, `Extensions/UTType/*`, `Extensions/FileManager/*`.
- **RyukSign:** `Backend/Observable/{TweakManager,TweakModels,AppUpdateChecker,BatchJobRunner,WebManager,...}.swift`, `Backend/Server/WebManagerServer*.swift`, `Views/Tweaks/*`, `Views/Settings/{Updates,Web Manager,Storage,Backup}/*`.
- **LiveContainer/FlekDeck:** blocked workstream; only Mach-O fixups currently reused.
- **SideStore:** SideSign already vendored; refresh/backup as separate workstream.

## 9. Non-goals

- Do not merge Ksign/RyukSign/Feather signing engines into one; keep Zsign as the single signing engine.
- Do not adopt LiveContainer app hosting without an approved security gate.
- Do not adopt FlareStore/Zeus/FeatherPlus until identities are verified.
- Do not break the existing Core Data non-destructive recovery or signing-failure propagation guarantees.
