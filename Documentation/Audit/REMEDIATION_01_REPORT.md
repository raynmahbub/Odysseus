# Remediation 01 report — security and reliability

**Date:** 2026-10-31
**Baseline:** `10f56462b41e04db33784c3e3fbbfdcad6a83b8f` (the audit commit), branch `arena/de5ddc0d-odysseus`, working tree clean before edits
**Scope:** the verified priority-1 and priority-2 findings from `ODYSSEUS_SECURITY_REVIEW.md` and `ODYSSEUS_BUG_AND_RELIABILITY_AUDIT.md`, plus the import/download state defects
**Out of scope and deliberately untouched:** new signing engines, source stores, tweak injection, app management, broad refactors

> **Branch note.** The task asked for `arena/odysseus-remediation-01`. This session is bound to `arena/de5ddc0d-odysseus`, which already sat at the audit commit; work stayed there rather than detaching from the session. Nothing was committed, pushed, merged or tagged.

---

## 1. Verification method and its limit

Every finding below was re-read in the current source before any edit; file paths and line numbers in §3 are from that read. **Nothing was built or executed**: this environment has no Xcode, no Swift toolchain, no simulator and no device (`swift --version` and `xcodebuild -version` both fail; the submodules `Zsign` and `IDeviceKitten` are unpopulated).

What *was* executed here:

| Check | Command | Result |
|---|---|---|
| Swift syntax balance (braces/parens, string- and comment-aware) on all 21 changed or added Swift files | local Python scanner | all balanced |
| `Info.plist` well-formedness and new key present | `plistlib.load` | parses; `NSLocalNetworkUsageDescription` present |
| Residual force-unwrap / `print` / direct-password-read scan | `grep -rn` | see §6 |
| Test-case count | `grep -c 'func test'` | 28 new cases in 4 new files (44 total) |

**No XCTest case in this repository has been run by this task.** The existing suite passed in CI at `2a54e3b`/`fe0f37e` (runs `41198043032`, `41219757550`); the new tests have never been compiled. §5 states this plainly rather than reporting them as passing.

---

## 2. Findings: verified, fixed, and not fixed

| ID | Finding | Verified at HEAD | Action |
|---|---|---|---|
| **S-01** / **ODY-BUG-001** | Certificate export put the `.p12` password into a caller-supplied URL unescaped, with no biometric gate and no destination shown | **yes** (`FR.swift` export function; `FeatherApp.swift` template comment) | **Fixed (code)** — see §3.1 |
| **S-03** | `.p12` password stored in the Core Data attribute; key material copied into an unprotected `Documents/` tree | **yes** (`Storage+Certificate.swift`, `CertificateFileHandler.swift`) | **Fixed for the password; partially fixed overall** — see §3.2 |
| **S-13** / **ODY-BUG-006** | Certificate delete swallowed file-removal failure and removed the record anyway | **yes** (`Storage+Certificate.swift:46–52`) | **Fixed** — see §3.2 |
| **S-04** | Install server bound to `0.0.0.0`, no access control, no local-network purpose string | **yes** (`ServerInstaller+TLS.swift:36`, `Info.plist`) | **Partially fixed** — declaration added, routes now under a per-install secret, server stops at terminal state; **binding unchanged by design** — see §3.3 |
| **ODY-BUG-002** | A throw during file prep/import left a permanent "downloading" row | **yes** (`DownloadManager.swift` catch → `print`) | **Fixed** — see §3.4 |
| **ODY-BUG-003** | Import failures were reported as "Download failed" | **yes** (`handlePachageFile` discarded `err`) | **Fixed** — see §3.4 |
| **ODY-BUG-004** | The 3-second timer could discard a slow import after it had succeeded | **yes** (`ODSignPipeline.downloadEnded` / `_didImport`) | **Fixed** — see §3.4 |
| **ODY-BUG-016** | `print` calls bypass the diagnostics export | **yes** (3 sites) | **Partially fixed** — the one on the import-failure path is now `Logger`; the two in the background managers are untouched |
| **C18** | Post-sign verification is a presence check | **yes** (`ZsignHandler.swift:121–130`), but the outcome path already fails closed on false return, missing callback, callback failure, or missing signature | **No change** — not a "failure converted into success" defect. The *limitation* (presence check, not cryptographic validation) remains and is recorded in §7 |
| **S-02** | Silent certificate import via `odysseus://import-certificate` | **yes** (`FeatherApp.swift:97–144`) | **Not fixed** — deliberately deferred to its own change (§7.1) |

---

## 3. Fixes

### 3.1 Certificate export no longer emits an unescaped secret

**Root cause.** `FR.exportCertificateAndOpenUrl(using:)` percent-encoded the certificate blob but substituted `certificate.password` into the caller's template by plain string replacement, then passed the result to `UIApplication.shared.open`. A password containing `&`, `+`, `#`, `%` or a space either truncated the link or spilled into the URL as a literal secret. The confirmation alert did not say where the certificate was going, and nothing gated the export behind device authentication.

**Change.**

| File | Change |
|---|---|
| `Feather/Backend/Certificates/ODCertificateExport.swift` *(new)* | Pure URL builder: strict unreserved-set encoding for both values, required `$(BASE64_CERT)` placeholder, optional `$(PASSWORD)`, 8 KB cap, destination description |
| `Feather/Backend/Security/ODDeviceAuthentication.swift` *(new)* | `LocalAuthentication` wrapper; returns `false` when no passcode/biometry is enrolled so the caller fails closed |
| `Feather/Utilities/FR.swift` | Builds the URL through the helper, names the destination in the confirmation, requires device-owner authentication before `open`, and refuses (with an explanation) when the link would be too long |

**Behaviour changes worth noting.**

- Export now requires Face ID/passcode. On a device with **no passcode set**, export is refused — intentionally fail-closed for key material.
- A template without `$(BASE64_CERT)` is rejected instead of exporting literal placeholder text.
- The wire format is unchanged: the password is still transmitted raw (percent-encoded for transport), because the documented consumer expects that form. **The exporter/importer mismatch noted in ODY-BUG-001 is therefore still open** — Odysseus's own importer base64-decodes the password and cannot read a URL Odysseus itself produced. Changing that is a contract decision (it would break the external consumer the feature was built for), so it is recorded as remaining work (§7.2) rather than silently changed.

**Tests** — `OdysseusTests/ODCertificateExportTests.swift` (9 cases): reserved-character round trip, base64 blob round trip, raw password never appears in `absoluteString`, missing placeholder rejected, cert-only template accepted, oversized URL rejected, empty password, destination description with and without a host.

### 3.2 Certificate passwords move to the keychain; deletion fails closed

**Root cause.** `Storage.addCertificate` wrote the plaintext password to `CertificatePair.password`, an ordinary Core Data attribute inside the app container (backed up, and reachable through `UIFileSharingEnabled`). `deleteCertificate` used `try?` on file removal and deleted the record regardless, so a failed delete left the private key on disk behind a UI that said it was gone.

**Change.**

| File | Change |
|---|---|
| `Feather/Backend/Certificates/ODCertificatePasswordStore.swift` *(new)* | `ODCertificatePasswordStoring` protocol + keychain implementation on the existing `ODKeychain`. Writes are **read back** before being reported successful, because `ODKeychain` discards `SecItem` statuses |
| `Feather/Backend/Storage/Storage.swift` | `certificatePasswords` dependency injected through `init(…, passwordStore:)` (defaults to the keychain store) |
| `Feather/Backend/Storage/Storage+Certificate.swift` | Password stored before the record is created and never written to Core Data; `password(for:)` resolves keychain → legacy attribute and migrates on read; `deleteCertificate` removes files first, then the secret, then the record, and returns `false` if the files cannot be removed |
| `Feather/Backend/Odysseus/ODSignPipeline.swift` | Signing reads the password through `Storage.password(for:)` |
| `Feather/Backend/Certificates/ODX509.swift` | OCSP leaf extraction reads the password through the same resolver (this call site was easy to miss — it built the p12 with `cert.password` directly) |
| `Feather/Utilities/Handlers/CertificateFileHandler.swift` | `addToDatabase()` now propagates a storage failure; new `cleanup()` removes the copied files |
| `Feather/Utilities/FR.swift` | On import failure the copied `.p12`/profile are deleted, so no key material is left without a record |
| `Feather/Views/Settings/Certificates/CertificatesView.swift` | Surfaces the "couldn't delete" case instead of silently doing nothing |

**Migration.** No upgrade step is needed: the first read of a certificate's password copies any legacy value into the keychain and clears the attribute. The Core Data attribute stays in the model (unused) to avoid an unversioned-model migration.

**Tests** — `OdysseusTests/ODCertificateSecretStorageTests.swift` (5 cases, injected in-memory store): password absent from Core Data; legacy value migrated and cleared; keychain write failure creates no record; delete removes the secret and the record; missing password returns `nil`.

**Not addressed.** The `.p12` **files** still live in `Documents/Feather/Certificates/<UUID>/` with the default protection class, `Documents/` is still exposed by `UIFileSharingEnabled`, and nothing is excluded from backup. Moving that tree and setting protection attributes is a separate change with its own migration risk (§7.3).

### 3.3 Install server: declaration, unguessable routes, bounded lifetime

**Root cause.** The server listens on every interface (`0.0.0.0`) with four fixed routes — manifest, two icons, payload — plus an install page. Any host on the network could fetch the payload while an install was running, and the manifest declared no local-network purpose string.

**Why the bind address was not changed.** In "Semi Local" mode the manifest and payload URLs point at the device's LAN address (`ServerInstaller.sni()`), and the system installer fetches them from there; there is also an `ipFix` escape hatch. Rebinding to loopback would break the transport this app documents and supports, so the reachability stays and the guessability goes.

**Change.**

| File | Change |
|---|---|
| `Feather/Resources/Info.plist` | `NSLocalNetworkUsageDescription` added |
| `Feather/Backend/Server/ODInstallRouteSet.swift` *(new)* | Per-install 128-bit secret; paths for manifest, payload, both icons and the install page are all scoped under it |
| `Feather/Backend/Server/ServerInstaller.swift` | Owns the route set; route dispatch compares against it (`if`/`else` rather than a value-pattern `switch`); new `stop()` |
| `Feather/Backend/Server/ServerInstaller+Compute.swift` | Every endpoint URL is built from the route set |
| `Feather/Views/Odysseus/Install/ODInstallSheet.swift`, `Feather/Views/Library/Install/InstallPreviewView.swift` | `installer.stop()` when the install reaches `.completed`/`.broken` instead of waiting for deallocation |

**What this does and does not achieve.** A LAN peer can no longer guess `/install`, `<uuid>.plist` or `<uuid>.ipa`; without the secret (carried only inside the URLs handed to the system installer) the routes return 404. The secret is a capability URL, not authentication: anyone who observes the URLs can still fetch the payload while the server runs, and the server still listens on all interfaces. **This is a partial mitigation, not a solved problem** — see §7.4.

**Tests** — `OdysseusTests/ODInstallRouteSetTests.swift` (6 cases): every path carries the secret, paths are distinct and stable, two installs never share routes, secret-less paths do not match, generated secrets are unique and well-formed, weak secrets are rejected. Routing and lifecycle have **no automated coverage** (they need Vapor + a real socket); §5 gives the manual checks.

### 3.4 Import/download state can no longer lie or dead-end

**Root causes (three).**

1. `urlSession(_:downloadTask:didFinishDownloadingTo:)` wrapped create/move/import in `do/catch` whose `catch` only called `print`. The row stayed in `downloads`, `downloadEnded` was never called, and the id stayed pending — the entry could not recover.
2. `handlePachageFile` discarded the import error (`if err != nil` only played a haptic), so the eventual failure message was the generic "Download failed".
3. `ODSignPipeline.downloadEnded` removed the id from `_pendingGets` after three seconds; `_didImport` began with `guard _pendingGets.remove(downloadID) != nil`. A slow import (large IPA, busy device) lost the race, was discarded, and the user saw "Download failed" for an app that had actually been imported but never signed.

**Change.**

| File | Change |
|---|---|
| `Feather/Backend/Odysseus/ODImportTracking.swift` *(new)* | Pure tracking type with a bounded recovery window (32 ids): `begin`, `downloadStopped`, `imported`, `forget` |
| `Feather/Backend/Odysseus/ODSignPipeline.swift` | `_pendingGets` replaced by `_tracking`; `downloadEnded` keeps the id recoverable when the timer expires; new `downloadFailed(_:error:)` and `importFailed(_:error:)`, both ignored for ids that are no longer tracked (so cancelling a Get does not produce a failure message) |
| `Feather/Backend/Observable/DownloadManager.swift` | Failure path in `didFinishDownloadingTo` now deletes the partial file, removes the row, stops the background task, and reports through `downloadFailed`; import errors go to `importFailed`; `didCompleteWithError` forwards the real error instead of a generic message after 3 s |

**Tests** — `OdysseusTests/ODImportTrackingTests.swift` (8 cases), including the exact regression: import after `downloadStopped` is still signed; plus unknown-id, cancellation, double-stop, single-consumption and window-bound cases.

**Not addressed.** The three-second grace period still exists as a heuristic for a *missing* import; it no longer destroys a late one. A deterministic terminal signal from the import stage is the proper fix and is part of roadmap ODY-002's follow-up (§7.5).

---

## 4. Exact files changed

**Added (9)**

```
Feather/Backend/Certificates/ODCertificateExport.swift
Feather/Backend/Certificates/ODCertificatePasswordStore.swift
Feather/Backend/Security/ODDeviceAuthentication.swift
Feather/Backend/Odysseus/ODImportTracking.swift
Feather/Backend/Server/ODInstallRouteSet.swift
OdysseusTests/ODCertificateExportTests.swift
OdysseusTests/ODCertificateSecretStorageTests.swift
OdysseusTests/ODImportTrackingTests.swift
OdysseusTests/ODInstallRouteSetTests.swift
```

**Modified (13)**

```
Feather/Backend/Certificates/ODX509.swift
Feather/Backend/Observable/DownloadManager.swift
Feather/Backend/Odysseus/ODSignPipeline.swift
Feather/Backend/Server/ServerInstaller.swift
Feather/Backend/Server/ServerInstaller+Compute.swift
Feather/Backend/Storage/Storage.swift
Feather/Backend/Storage/Storage+Certificate.swift
Feather/Resources/Info.plist
Feather/Utilities/FR.swift
Feather/Utilities/Handlers/CertificateFileHandler.swift
Feather/Views/Library/Install/InstallPreviewView.swift
Feather/Views/Odysseus/Install/ODInstallSheet.swift
Feather/Views/Settings/Certificates/CertificatesView.swift
```

No third-party code was copied; no licence or notice file changed; no dependency was added, removed or re-pinned. The project uses `PBXFileSystemSynchronizedRootGroup` folders, so the new files need no `project.pbxproj` edit.

---

## 5. Tests and builds: what ran, what did not

### 5.1 Not run — and why

| Item | Status | Reason | Command for a capable machine |
|---|---|---|---|
| `xcodebuild test` (all 44 cases) | **NOT RUN** | No Xcode/`xcodebuild`, no simulator, no Swift toolchain on this host | `xcodebuild test -project Feather.xcodeproj -scheme Feather -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO` |
| `make iphoneos` | **NOT RUN** | Same; also requires populated submodules | `git submodule update --init --recursive && make iphoneos` |
| `scripts/verify_ipa.sh` | **NOT RUN** | Needs a produced IPA | `scripts/verify_ipa.sh packages/Odysseus.ipa` |
| Any device or simulator behaviour | **NOT RUN** | No device | §5.3 |

**No test result in this report is observed.** If a build error appears, the most likely places are the new `withCheckedThrowingContinuation` in `CertificateFileHandler`, the `CocoaError` pattern in `deleteCertificate`, and the Vapor route closure in `ServerInstaller` — each is small and isolated, and none changes a public signature used outside its file.

### 5.2 Executed here (static)

| Check | Result |
|---|---|
| Brace/paren balance, all 21 changed files | balanced |
| `Info.plist` parses; local-network key present | pass |
| Import resolution for every changed file (`NimbleExtensions`, `OSLog`, `LocalAuthentication`, `Security`) | one missing import found and fixed (`ODCertificatePasswordStore`); no others |
| Call-site signature cross-check (`makeURL`, `authenticate(reason:)`, `Storage(storeURL:passwordStore:)`, `addCertificate(…)`, `ODSignError.importFailed`, `downloadFailed/importFailed`, `_tracking` mutability) | all match |
| `grep` for `cert.password` direct reads | only `Storage+Certificate` internals remain (migration code) |
| `grep` for `_pendingGets` | only a comment in `ODImportTracking` |
| `grep` for `print(` | 2 remain (`BackgroundAudioManager`, `BackgroundTaskManager`), both out of scope |

### 5.3 Required manual/device verification

1. **Export**: export a certificate using a password containing `&`, `+`, `%` and a space; the receiving app must recover the exact password. Repeat with Face ID cancelled — export must not happen. On a device without a passcode — export must be refused with the explanation.
2. **Certificate migration**: on a build that previously stored a password, read it (sign an app) and confirm signing still works; then confirm `CertificatePair.password` is empty in the store.
3. **Delete**: delete a certificate and confirm the `<UUID>` directory is gone; then simulate an unremovable directory and confirm the alert appears and the certificate stays listed.
4. **Install (both transports)**: Semi Local (`serverMethod == 1`, with and without `ipFix`) and Fully Local TLS — the manifest must load and the app must install. This is the highest-risk change in the patch: it exercises the new secret-scoped routes.
5. **Server lifetime**: after `.completed`/`.broken`, confirm the port is closed (`nc -z <device-ip> <port>` from another host fails).
6. **Import failure**: fetch an app with a corrupt/oversized IPA; the row must disappear with an import-specific message, and re-fetching must work.
7. **Slow import**: fetch a large IPA and let the import take >3 s; it must still reach signing instead of reporting "Download failed".
8. **Cancel**: cancel a Get mid-download; no failure message should appear.

---

## 6. Residual risks (all still open)

| Risk | Why it remains | Severity |
|---|---|---|
| Certificate still leaves the app inside a URL | Inherent to the export design the feature was built for; the destination is now shown and gated, but the secret is still in a URL | Medium |
| Export → import round trip remains incompatible (raw vs base64 password) | Changing either side breaks an external consumer; needs a contract decision | Medium |
| `.p12` files unprotected, `Documents/` exposed, backed up | Separate file-tree migration | High |
| Install server reachable on the LAN during an install | Binding retained for the supported transport; secret only prevents enumeration | Medium |
| The secret-bearing payload URL is sent to the configured external plist service | `externalServerLink` posts `fetchurl=<payload url>` to `api.palera.in` (or a custom server) whenever that mode is selected. Pre-existing behaviour, not made worse — the old URL was guessable — but the secret now leaves the device | Low |
| No nonce on OCSP requests, 1-hour trust window | Untouched (S-06) | Medium |
| Unpinned dependencies, four AGPL packages | Untouched (L-01/L-02) | High |
| `try!` sites remain (`AR.swift:14`, `ServerInstaller+TLS.swift:19–20`), `as!` in `ODX509.swift:172` | Out of the selected scope | Medium |
| `BGTaskScheduler` late registration | Untouched (ODY-BUG-005) | High |

## 7. Recommended next remediation

1. **S-02 / silent certificate import** — require an explicit, named confirmation before `odysseus://import-certificate` stores an identity, and stop letting an unconfirmed certificate become the default. Small, self-contained, and the last priority-1 item.
2. **Resolve the export/import password contract** — pick one encoding, document it in the deep-link comment, and make importer and exporter agree (S-01 follow-up).
3. **Certificate directory hardening** — move key material out of `Documents/`, apply `completeUntilFirstUserAuthentication`, exclude from backup, and turn off or narrow `UIFileSharingEnabled` (S-03 remainder).
4. **ODY-BUG-005** — register background tasks before launch with a fixed identifier. This one cannot be validated without a device and should carry a device test with it.
5. **Dependency pinning + notices** (L-01/L-02) — mechanically simple, release-blocking for distribution.

Each is deliberately *not* part of this patch so it can be reviewed and reverted independently.
