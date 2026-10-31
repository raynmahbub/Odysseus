# Odysseus baseline source audit

**Audit date:** 2026-10-31 (UTC)
**Repository revision:** `2664dadedf9aca36fda0925a8aada92e2c79323f` (`Fix tint presets list`)
**Working branch:** `arena/438d62e5-odysseus`
**Scope:** establish the existing app, architecture, implementation state, build evidence, and highest-risk defects before feature integration. This is a static source audit plus a review of the existing GitHub Actions result; it is not an iOS device-security certification.

## Executive summary

Odysseus is a substantial Feather-derived iOS app, not a template. It has a SwiftUI storefront and library, AltStore-style source fetching, certificate-based Zsign signing, a SideSign-based Apple ID signing path, certificate-status checks, and two installation paths. The newer Odysseus code shares existing Feather storage and signing machinery rather than replacing it wholesale. This is a useful foundation for controlled integration.

There is also real build evidence: the exact baseline commit passed the existing macOS GitHub Actions build on 2026-10-07. That job produced and uploaded the IPA and completed its nightly-publish step. It did **not** run tests or validate installation/signing on a device. The local audit environment is Linux and has neither `xcodebuild` nor Swift, so I could not reproduce that build locally.

**Do not treat the README feature list as an end-to-end verification.** The audit found a likely live TLS private key embedded in build artifacts, a post-signing bundle mutation, unsafe Core Data queue use in detached tasks, and signing-error propagation gaps. These should be addressed and covered by tests before adding more signing/install implementations.

## What is in the repository

- One Xcode application target and shared scheme: internally named **Feather**, product/display name **Odysseus**. The iOS deployment target is 17.0; iPhone and iPad are targeted. The project enables Mac Catalyst, and `Makefile` has a Catalyst target, but CI only builds the iOS IPA.
- App code remains in the `Feather/` tree. Odysseus additions are mainly under `Backend/Odysseus`, `Backend/AppleID`, `Backend/Certificates`, and `Views/Odysseus`; existing Feather screens and handlers remain in use.
- Local packages: AltSourceKit and NimbleKit. Git submodules: Zsign and IDeviceKitten. I initialized the two pinned submodules for this audit; CI already checks them out recursively.
- Project dependencies also include Vapor, Zip, SWCompression, Nuke, LicensePlist, BitByteData, SideSign and its Apple ID/anisette dependencies, OpenSSL, and the IDevice binary framework. SideSign is vendored under its own AGPL-3.0 license; root/third-party license files and `license_plist.yml` are present.
- There is a Core Data model named `Feather`, a shared `Feather` workspace, a shared `Feather` scheme, and one app target. I found no test sources, test target, or test plan; the scheme's `TestAction` has no testables.

## Architecture and ownership today

| Concern | Current owner / path | Audit assessment |
|---|---|---|
| App/UI | SwiftUI `ODRootView`, `ODDiscoverView`, `ODLibraryView`, `ODSettingsView`; Feather views retained | Coherent user-facing Odysseus layer, but still one app target with legacy and new screens mixed together. |
| Source/catalog | `SourcesViewModel`, `ODCatalogStore`, `ODCatalog`; AltSourceKit + NimbleJSON | Sources are persisted in Core Data; catalog is assembled in memory. No source/catalog test suite. |
| Persistence/files | `Storage` and `Storage+…` extensions; `Documents/{Signed,Unsigned,Certificates,Archives}` | Core Data view context plus filesystem payloads; current queue and recovery behavior needs hardening. |
| Signing | `ODSignPipeline` → Feather `SigningHandler` → `ZsignHandler`/Zsign | One shared route selects imported certificate or Apple ID, which is a good integration point. Zsign's error contract is not safely consumed. |
| Apple ID | `ODAppleIDManager`, `ODKeychain`, SideSign | Implements login/2FA, anisette, team/certificate/device/App ID/profile work, and export; live Apple portal behavior/device signing remains unverified. |
| Revocation | `ODOCSPChecker`, `ODOCSPCore`, `ODX509`, `ODDER`, `ODCertificateStatusStore` | Substantial custom OCSP implementation; freshness and signature-verification outcomes need security tests. |
| Installation | `ArchiveHandler`, Vapor `ServerInstaller`, IDevice/InstallationProxy pairing path | Both paths exist in code. The default server mode is semi-local; platform/entitlement behavior and actual installs need device testing. |
| CI | `.github/workflows/build.yml`, `Makefile` | One build/release workflow, no test/lint/static-analysis job. The IPA packaging path has security and signature-order concerns below. |

`ODSignPipeline` is the strongest existing integration seam: Discover's Get flow, direct signing, and Apple ID/certificate selection converge there. New signing or installation mechanisms should be introduced as explicit adapters behind this path, not as parallel UI-specific flows.

## Feature status: source presence versus proof

| Capability | Source status | What is / is not verified |
|---|---|---|
| Discover storefront, search, categories, featured/recent rows, duplicate grouping | Implemented in source | No catalog tests or live source compatibility matrix. |
| Add/import/export AltStore-style sources, QR scanning, automatic refresh | Implemented in source | No retry/failure tests; source fetch behavior is not validated against hostile or malformed feeds. |
| Import IPA/TIPA, library organization, app customization, tweak injection | Implemented in Feather/Odysseus handlers and views | Not exercised on-device in this audit. |
| Sign with imported `.p12` + `.mobileprovision` | Implemented through Zsign | Build success does not establish that every signing result is valid; error handling has a high-priority defect below. |
| Apple ID signing | Implemented through SideSign and Zsign | Live Apple authentication, profile issuance, free-account limits, and installation require device/account tests. The anisette endpoint is a configurable external service. |
| OCSP status, notifications, expiry reminders, revoked-certificate policy | Implemented in source | Not covered by tests; OCSP freshness/signature handling is not strong enough to call security-verified. |
| Local server and pairing-file/LocalDevVPN install | Implemented in source | No device result in this audit. `Feather.entitlements` contains only `get-task-allow`; documentation notes fully local mode depends on entitlements, while semi-local mode is the registered default. |
| Features from FeatherPlus, KSign, RyukSign, FlareStore, LiveContainer, SideStore, Zeus, and FlekDeck | Not audited/integrated in this phase | Their source trees, exact feature provenance, compatibility, and licenses remain Phase 2 work. Current code credits SideSign/SideStore and a LiveContainer Mach-O fix; those credits do not mean the full reference apps are integrated. |

## Findings to resolve before broad integration

Severity is a prioritization aid, not a formal CVSS score.

### Critical — build artifacts appear to contain a shared TLS private key

`Makefile:21–24` downloads `pack.json`, extracts `.key1` and `.key2` into `deps/server.pem`, then `Makefile:49` copies all of `deps/` into the built app bundle and IPA. `ServerView.ServerPackModel` reconstructs the same `key1 + key2` value, `FR.downloadSSLCertificates` writes it as `server.pem`, and `ServerInstaller+TLS` loads that file as its TLS private key. This is therefore not just a certificate-chain file: the build path packages the server private key used by the app.

If the endpoint returns a live key for the advertised certificate, every distributed IPA discloses it. Treat that key as public/compromised and rotate it at its owner; do not distribute a shared server private key in the app. Replace this with per-device key generation or a design that does not ship a private key. The endpoint was not fetched during this audit.

### High — the IPA bundle is modified after it is code-signed

`Makefile:48` runs `codesign`, then `Makefile:49` copies the certificate, private key, and common-name files into the `.app`. Those post-signing resource changes invalidate the bundle's existing code-signature seal. The workflow only checks that `packages/Odysseus.ipa` exists (`build.yml:64–70`); it does not verify the packaged app signature. This is consistent with a workflow that can pass while producing an IPA that fails signature verification or installation. Copy required resources before signing and add a macOS `codesign --verify`/IPA inspection check.

### High — Core Data's main-queue context is accessed from detached work

`Storage.context` is `container.viewContext` (`Storage.swift:31–33`). Both `FR.handlePackageFile` and `FR.signPackageFile` start `Task.detached` work (`FR.swift`), while `AppFileHandler.addToDatabase` creates an `Imported` object via `Storage.addImported`, and `SigningHandler` reads/manipulates managed objects and creates a `Signed` object via `Storage.addSigned`. Those operations use the view context outside its main queue. This can trigger Core Data concurrency violations, dropped imports, or nondeterministic state. Keep all view-context access on its owning actor/queue (or move the workflow to a private context and pass value snapshots).

### High — Zsign failures can be reported as success or leave a broken Library entry

`ZsignHandler.sign()` discards the Boolean returned by `Zsign.sign()` (`ZsignHandler.swift:52–83`). The Zsign C wrapper can return early without invoking its completion callback, leaving `hadError` nil. In addition, `SigningHandler.modify()` moves the result and inserts the `Signed` Core Data record before checking `hadError` (`SigningHandler.swift:129–134`). A bad key/profile or partial sign may therefore be accepted as success, or an error may be shown after a broken artifact has already been stored. Propagate both the Boolean and callback error and only move/register after signing has definitively succeeded.

### High — OCSP data is not checked for response freshness, and “good” can outlive verification

`ODOCSPCore` parses `thisUpdate` and `nextUpdate`, but `ODOCSPChecker.check()` does not validate either against the current time before returning a status. It also returns `.valid` for a `good` response when signature verification is `.unverifiable`, merely adding a detail string (`ODOCSPChecker.swift:116–153`). Since the signing pipeline uses this stored status in its revoked-certificate gate, stale or unverifiable data can be presented as valid. Validate responder authorization/signature and the response validity window; add tests for stale, malformed, unknown, bad-signature, and revoked responses before relying on “Block Signing.”

### High — Core Data recovery deliberately deletes user payloads

If the persistent store fails to load, `Storage._destroyStore` removes the SQLite store and the entire `Documents/Signed`, `Documents/Unsigned`, and `Documents/Certificates` trees (`Storage.swift:53–85`) before retrying. A migration/store issue can therefore erase signed apps, imported apps, certificates, and private-key files rather than preserving them for recovery. Back up/move data and use a non-destructive migration/recovery path; do not delete user payloads as a store-load fallback.

### Medium — Apple ID signing material is not cleaned up on failure

`prepareSigning()` writes the Apple ID `.p12` and profile to a UUID-named temporary directory (`ODAppleIDManager.swift:561–577`). `ODSignPipeline.sign()` removes that directory only after `FR.signPackageFile` succeeds (`ODSignPipeline.swift:181–199`). A thrown signing error skips cleanup, leaving certificate material in temporary storage. Use guaranteed cleanup (`defer`/scoped temporary storage) on success, failure, and cancellation, and protect both files consistently.

### Medium — the global “Delete IPA After Signing” setting cannot reliably turn deletion off

`ODPrefs.registerDefaults()` sets `autoDeleteIPAs` to `false` (`ODPrefs.swift:42–53`), and the pipeline only forces `post_deleteAppAfterSigned` to `true` when that preference is true (`ODSignPipeline.swift:131–133`). But `Options.defaultOptions` initializes `post_deleteAppAfterSigned` to `true` (`OptionsManager.swift:157–158`). On a fresh install the setting being off does not override the signing option, so the imported app can still be deleted. Make the preference authoritative and cover both settings states with tests.

### Medium — build and runtime validation gaps

- The build downloads a live external dependency from `backloop.dev` (`Makefile:6, 21`), so IPA production is coupled to that service's availability and key rotation. Keep private deployment material out of CI outputs and make routine builds reproducible.
- There is no app-level `Package.resolved`; `SideSign/Package.swift` includes dependencies tracked by `main`/`master` branches. The tracked `SideSign/Package.resolved` may not lock dependencies when SideSign is consumed as a local package by the app. Commit/verify a root workspace resolution lock.
- `ServerInstaller._setup()` swallows setup errors with `try?`, and both install sheets construct it with `try!`. A server/port/TLS setup problem can become a failed or crashing install flow instead of a surfaced diagnostic.
- The recommended-source fetch in `SourcesAddView` schedules result appends in unstructured `Task { @MainActor … }` blocks but resumes the checked continuation immediately (`SourcesAddView.swift:183–204`). The task group does not explicitly wait for those appends, so recommended-source results may be incomplete. `SourcesViewModel` also advances the last-refresh timestamp after a batch even when some/all sources failed.

## Build and validation status

### Existing CI evidence

The exact audited revision has a successful GitHub Actions run:

- **Run:** [37659670246](https://github.com/mirazbakis/Odysseus/actions/runs/37659670246)
- **Commit:** `2664dadedf9aca36fda0925a8aada92e2c79323f`
- **Job:** `Build unsigned Odysseus.ipa` — success
- **Date:** 2026-10-07
- **Steps:** Xcode setup, versioning, `make iphoneos`, IPA artifact upload, and nightly publish all succeeded.

This is a strong baseline **build/package** result. It is not proof of device installation, certificate signing correctness, Apple ID portal compatibility, or OCSP correctness. The workflow has no test job and the scheme has no testables.

### Checks performed for this audit

- Initialized and inspected the Git-pinned Zsign and IDeviceKitten submodules.
- Reviewed the project/target settings, `Makefile`, Actions workflow, source/catalog, persistence, signing, Apple ID, OCSP, installation, and settings paths.
- Parsed the app plists/entitlements, Core Data model, scheme/storyboard XML, source/config JSON, and asset-catalog JSON successfully.
- Ran `make -n iphoneos` to inspect the packaging commands; did **not** run the build because this environment is Linux and does not provide `xcodebuild`, `swift`, or `swiftc`.
- Found no unit/integration test source or target.

## Recommended order from this baseline

1. Stop bundling the TLS private key; rotate the shared key if it is real, and correct the sign-then-copy packaging order with signature verification in CI.
2. Fix signing success/failure propagation and Core Data queue ownership before changing sign/install architecture.
3. Harden and unit-test OCSP response verification/freshness; preserve user data on Core Data recovery; guarantee temporary-key cleanup.
4. Add app-level test targets and CI test/static checks. Keep the current macOS IPA build workflow; extend it rather than adding a competing build pipeline.
5. Then perform Phase 2: audit each of the nine reference projects for feature overlap, platform constraints, dependency provenance, and license/attribution obligations. No bulk feature integration was started in this baseline-audit step.
