# Odysseus security and reliability remediation report

**Status:** implementation and regression tests added; native macOS/Xcode validation is pending.
**Branch:** `arena/03624e7c-odysseus` (kept as supplied by the workspace; no branch switch).
**Base:** `882ef8e2ad958d9a41463e61b62608c885315732`.
**Scope:** security/reliability remediation only. No reference-project feature integration, release, tag, or app-identity/version change.

The historical source audit is recorded in [`BASELINE_AUDIT.md`](BASELINE_AUDIT.md). This report records the remediation state relative to the base above.

## Findings and changes

### TLS credentials and IPA packaging

- Removed the build-time download of `backloop.dev/pack.json` and the copy of its certificate/key into the app. Fully Local mode now requires the user to import a matching certificate chain, private key, and hostname. The files are validated before activation and again at server startup, stored under protected Application Support with restrictive permissions and backup exclusion, and never silently replaced by HTTP or a shared credential. Semi Local and pairing installation paths remain available.
- Removed the old `Documents/server.pem`, `server.crt`, and `commonName.txt` artifacts on launch; cleanup failures are logged. Temporary document-picker copies are removed after reading, with cleanup failures logged.
- The IPA recipe now copies the final `.app` into `Payload/` before ad-hoc signing. CI runs `scripts/verify_ipa.sh` on the packaged IPA to check its layout, app identity/version/minimum iOS, final signature, provisioning-profile state, and bundled private-key indicators.

**Credential status and rotation:** the old pack endpoint was not fetched, so its present contents, key owner, and validity/revocation status are unknown. The repository no longer downloads or packages it, but this does not revoke copies distributed previously. The service/key owner must rotate or revoke any formerly shared key if it was real and remains in use. Fully Local users must provide their own currently trusted server identity.

### Signing failure propagation

- Zsign's Boolean return, callback success/error, callback presence, and main-executable signature presence are required before the signed app is moved into Library storage or recorded in Core Data. Malformed bundle metadata and missing install URLs now fail explicitly.
- Signing inputs are snapshotted before detached work, and the app's existing IPA/TIPA import, extraction progress, and work-directory flow are retained.
- `Zsign.checkSigned` checks for signature presence; it is **not** cryptographic signature verification. Final package signature verification in CI is a separate check and does not replace verification of every Zsign-produced third-party app.

### Core Data concurrency and data preservation

- View-context access is main-actor-owned. Imports and signed records are saved on private contexts; only permanent object IDs and value snapshots cross queues. Archive/install paths no longer carry managed objects into detached work, and parallel source fetches collect child results directly instead of mutating a shared array.
- Persistent-store startup now has explicit loading/loaded/failed states. A load failure is surfaced in the UI and does not delete the SQLite store, retry destructively, or clear Library payload folders. URL imports and startup work are gated on store readiness.
- Single-record and reset deletions quarantine associated files, save the database change on a private context, restore files when the database operation fails, and report cleanup/restore failures. Reset actions no longer remove app/certificate folders after a failed record deletion.

### OCSP baseline checks

- CertID parsing now binds status to issuer-name hash, issuer-key hash, and serial; the responder identity must match; the response signature and issuer/delegated-responder trust must pass before a response can be considered valid. Cached signing decisions require a verified, determinate response inside its freshness window.
- The parser, delegated-responder EKU/key-usage authorization, and freshness checks have regression tests. The public Security trust evaluation, signature/trust behavior against real Apple responses, and live OCSP interoperability remain unverified until macOS/Xcode execution.

### Apple ID temporary signing material and auto-delete default

- Apple ID p12/profile material is written in a UUID-named `0700` temporary directory with `0600` files and complete file protection. Partial-write failures and normal signing completion attempt cleanup; cleanup failures are logged. Startup removes app-owned signing-material directories older than 24 hours while leaving recent directories untouched.
- New/reset signing options default `post_deleteAppAfterSigned` to `false`, aligned with the global default. Existing persisted `Options` are deliberately not migrated because the saved `true` value cannot be distinguished from an explicit user choice. Users with existing settings should inspect the per-signing deletion option.

## Changed paths

- **Build/package:** `.github/workflows/build.yml`, `Makefile`, `scripts/verify_ipa.sh`, `Feather.xcodeproj/project.pbxproj`, `Feather.xcodeproj/xcshareddata/xcschemes/Feather.xcscheme`.
- **TLS/server/UI/docs:** `Feather/Backend/Server/ODLocalServerTLS.swift`, `Feather/Backend/Server/ServerInstaller+TLS.swift`, `Feather/Backend/Server/ServerInstaller+Compute.swift`, `Feather/Backend/Server/ServerInstaller.swift`, `Feather/Views/Settings/Installation/Server & SSL/ServerView.swift`, `HOW_IT_WORKS.md`, `README.md`.
- **Signing/import/install:** `Feather/Backend/AppleID/ODAppleIDManager.swift`, `Feather/Backend/Odysseus/ODSignPipeline.swift`, `Feather/Utilities/FR.swift`, `Feather/Utilities/Handlers/AppFileHandler.swift`, `Feather/Utilities/Handlers/ArchiveHandler.swift`, `Feather/Utilities/Handlers/SigningHandler.swift`, `Feather/Utilities/Handlers/ZsignHandler.swift`, `Feather/Views/Library/Install/InstallPreviewView.swift`, `Feather/Views/Odysseus/Install/ODInstallSheet.swift`, `Feather/Views/Odysseus/Library/ODLibraryView.swift`, `Feather/Views/Common/FRAppIconView.swift`.
- **Persistence/concurrency/preferences:** `Feather/Backend/Storage/Storage.swift`, `Feather/Backend/Storage/Storage+Imported.swift`, `Feather/Backend/Storage/Storage+Signed.swift`, `Feather/Backend/Storage/Storage+Shared.swift`, `Feather/FeatherApp.swift`, `Feather/Views/Settings/Reset/ResetView.swift`, `Feather/Views/Sources/SourcesAddView.swift`, `Feather/Views/Sources/SourcesViewModel.swift`, `Feather/Backend/Observable/OptionsManager.swift`, `Feather/Backend/Odysseus/ODPrefs.swift`.
- **OCSP:** `Feather/Backend/Certificates/ODCertificateStatusStore.swift`, `Feather/Backend/Certificates/ODOCSPChecker.swift`, `Feather/Backend/Certificates/ODOCSPCore.swift`, `Feather/Backend/Certificates/ODX509.swift`.
- **Regression tests:** `OdysseusTests/ODAppleIDMaterialCleanupTests.swift`, `OdysseusTests/ODOCSPCoreTests.swift`, `OdysseusTests/ODOCSPFreshnessTests.swift`, `OdysseusTests/ODOCSPResponderAuthorizationTests.swift`, `OdysseusTests/ODZsignOutcomeTests.swift`, `OdysseusTests/StorageConcurrencyTests.swift`.

## Validation performed

- `bash -n scripts/verify_ipa.sh` — pass.
- `make -n iphoneos` — pass; this inspected commands only and did not build the app.
- Python OpenStep project parse with `py-pbxproj` and shared scheme XML parse — pass. These are syntax/structure checks, not Xcode build validation.
- Added 16 XCTest cases covering Zsign outcomes, OCSP CertID/responder-authorization/freshness rules, concurrent/persistent Core Data writes, certificate relationship lookup, failed-store/reset data preservation, auto-delete defaults, and stale Apple ID material cleanup. They are configured in the shared scheme but have not run here.
- `git diff --cached --check` — pass on the staged patch before commit; the IPA verifier is executable (`0755`).
- **macOS CI:** run `41189354559` failed during compilation on a missing closing brace in the source-fetch task group and `SecPolicyCreateOCSPSigner`, which is unavailable in the public iOS SDK. Run `41189947319` confirmed the remaining unavailable API error; run `41190659516` identified a `Text` initializer error; run `41191245878` found an unhandled throwing cache-clear call after the method was made throwing. The task-group closure, text initializer, and cache-clear call are fixed; the private API has been replaced with public basic-chain trust plus explicit delegated-responder EKU/key-usage checks. A rerun for the latest fixes is pending. No XCTest or IPA verification completed in those runs.
- **Not run locally:** `xcodebuild`, Swift compilation, XCTest, `codesign`, IPA verification against a real artifact, dependency resolution/audit, or device install. This workspace is Linux and lacks the Apple toolchain. A passing simulator job is not a device-install claim.

## Remaining developer actions and risks

1. Review macOS CI output and fix any compiler, XCTest, signing, or packaging failures before merge.
2. Exercise Fully Local TLS with an owned valid identity, Semi Local installation, pairing installation, certificate/Apple ID signing, and reset/recovery flows on supported iOS hardware. No device validation has been performed here.
3. Confirm ownership and operational status of the former shared TLS credential, and rotate/revoke it if it was active. Do not reuse or redistribute it.
4. Review existing users' saved auto-delete option as noted above. Confirm OCSP verification/freshness against current Apple responses and Security framework behavior.
5. Preserve the existing app name, bundle identifier, app version, iOS 17 minimum, and app signing settings; the project edit adds only a unit-test target/scheme entry.

## Suggested commit and changelog text

**Commit:** `fix(security): harden signing, TLS, and library persistence`

**Changelog:** Remove shared TLS-key packaging; require user-owned, protected TLS credentials for Fully Local mode; verify the final IPA and propagate signing failures; make Core Data writes/deletions queue-safe and non-destructive; tighten OCSP freshness/signature checks; and default imported-app cleanup to off. Add regression tests and macOS CI validation.
