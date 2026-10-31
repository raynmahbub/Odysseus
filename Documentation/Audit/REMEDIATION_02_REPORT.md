# Remediation 02 report — certificate lifecycle and install-server exposure

**Date:** 2026-10-31
**Starting branch and HEAD:** `arena/2decf72f-odysseus` @ `3731643df350aad872395e3553a78ed6e05ff535` (= `master` = `origin/master`; the repository is a single squashed commit, so there is no parent to diff against). Working tree was clean.
**Previous remediation:** `REMEDIATION_01_REPORT.md` at the same commit.
**Scope:** the leads left open by that report — export/import format, `.p12` protection and backup, install-server exposure, and incomplete diagnostics. No new features.

> **Branch note.** The task names `arena/odysseus-remediation-02`. This session is bound to `arena/2decf72f-odysseus`, which already sat at the remediation commit; work stayed there rather than detaching from the session. Nothing was committed, pushed, merged or tagged.

---

## 1. Method, and what "verified" means here

Each lead was traced in the current source before anything was edited; §3 cites the code that proved or disproved it. **No build, test or device run was performed**: this environment has no Swift toolchain, no Xcode, no simulator and no device (`swift --version` and `xcodebuild -version` both fail; the `Zsign` and `IDeviceKitten` submodules are unpopulated).

Checks that *were* executed:

| Check | Command | Result |
|---|---|---|
| Swift syntax balance (braces/parens, string/comment/interpolation aware) on all 20 changed or added Swift files | local Python scanner | all balanced |
| Module imports for every changed file (`NimbleExtensions`, `OSLog`) | `grep` cross-check | 3 missing imports found and fixed (`ODCertificateFiles`, `ODCertificateImportLink`, `CertificateFileHandler`) |
| API cross-check against the types actually in this tree (`Certificate` fields are non-optional, `Storage`, `FileManager`, `UIAlertController` helpers, `ServerInstaller` members) | manual read | one wrong assumption fixed (`Certificate.Name`/`TeamName` are `String`, not `String?`) |
| Secrets in log statements | `grep -rn "Logger\..*password"` | only UUID + generic text, no values |
| Test inventory | `grep -c 'func test'` | 54 new cases, 98 total |

**Nothing in §6 has been executed.** Where the report says a behaviour is "fixed", it means the code path was changed and reviewed statically; it does not mean it was observed running.

---

## 2. Findings

| # | Lead from Remediation 01 | Status in source | Action |
|---|---|---|---|
| L1 | Export writes the password **raw**; the importer base64-decodes it | **Verified.** `FR.exportCertificateAndOpenUrl` → `$(PASSWORD)` = raw; `FeatherApp._handleURL` → `Data(base64Encoded: passwordBase64)` | Fixed — both encodings accepted, exporter emits base64 too |
| L2 | Importer decoded query values twice (`removingPercentEncoding` after `URLComponents`) | **Verified** (`FeatherApp.swift`, old lines 104–119) | Fixed — single decode, in one pure parser |
| L3 | Exporter never emits a provisioning profile, but the importer requires one | **Verified.** Import requires `mobileprovision`; export only substituted `$(BASE64_CERT)`/`$(PASSWORD)` | Fixed — `$(BASE64_PROVISION)` (optional, opt-in by template) |
| L4 | `.p12` + profile stored in `Documents/Certificates`, with `UIFileSharingEnabled` on, default protection, included in backups | **Verified.** `FileManager.certificates` → `URL.documentsDirectory`; `Info.plist` has `UIFileSharingEnabled=true`; no protection attributes anywhere | Fixed — moved to `Application Support`, protected, excluded from backup, one-time migration |
| L5 | Import temp copies (`decodeAndWrite`) never deleted | **Verified.** `FeatherApp` wrote `.p12`/profile into `temporaryDirectory` and never removed them; every early `return` leaked them | Fixed — app-owned writer, deletion on success/failure/cancel |
| L6 | Cleanup might delete an unrelated file | **Not reproducible** for certificates (it only removed `certificates(uuid)`), but unguarded | Hardened — removal is limited to a direct child of the certificate root; temp cleanup only touches its own prefixed files |
| L7 | Install server listens on `0.0.0.0` | **Verified.** `ServerInstaller+TLS.swift`: `.hostname("0.0.0.0", port: port)` | Fixed for every transport except a TLS identity configured with a DNS name (§7) |
| L8 | No request-side access control beyond the route secret | **Verified** — no method/host checks existed | Fixed — GET-only plus `Host` validation, uniform 404 |
| L9 | Server kept running on cancel, and indefinitely if no terminal state | **Verified.** `stop()` existed but was only called on `.completed`/`.broken`; dismissal relied on deallocation | Fixed — stop on dismiss, after payload delivery, and on a 10-minute cap |
| L10 | Certificate import is silent: no confirmation, no authentication | **Verified** (`odysseus://import-certificate` stored an identity on a bare link) | Fixed — explicit confirmation naming the certificate |
| L11 | `CertificatesAddView` dismissed regardless of import failure | **Verified.** Completion was `{ _ in dismiss() }` | Fixed — failure keeps the sheet open and reports the error |
| L12 | `CertificateFileHandlerError` had no message | **Verified.** `private enum ... : Error` with no `LocalizedError` | Fixed — actionable messages |
| L13 | Export returned silently when the `.p12` file was missing | **Verified.** `guard ... else { return }` inside `performExport` | Fixed — explicit alert |
| L14 | Export deep link decoded `callback_template` a second time after `URLComponents` | **Verified.** `queryItems[...]?.removingPercentEncoding`, which returns `nil` for a template containing a bare `%` — the export then aborted with no message | Fixed — `ODCertificateExport.resolveTemplate` |
| — | Password in Core Data; delete not fail-closed; install routes guessable; missing `NSLocalNetworkUsageDescription` | **Already fixed** in Remediation 01; re-checked | No change |
| — | `ZsignHandler` "failures converted to success" | **Unconfirmed** (checked in Remediation 01; the outcome path fails closed) | No change |
| — | `try!` sites (`AR.swift:14`, `ServerInstaller+TLS.swift:19–20`), `as!` in `ODX509.swift:172` | **Verified present**, out of scope here | Not changed |

---

## 3. Root causes and fixes

### L1–L3 — the link format is now defined in one testable place

**Root cause.** Three independent encodings grew around one deep link. The exporter documented and produced `password=<raw>`; the importer required `password=<base64>` and a `mobileprovision` field the exporter never wrote; and the importer stripped percent-escapes a second time after `URLComponents` had already decoded, so a password containing `%` was corrupted even when the encoding matched. Odysseus could not import a link Odysseus produced, and an external caller could not know which format was current.

**Fix.**

| File | Change |
|---|---|
| `Feather/Backend/Certificates/ODCertificateImportLink.swift` *(new)* | Single parser: scheme/host check, single percent-decode, strict base64 with a size cap, and password candidates. Pure — no UIKit, files or device — so the whole format is testable |
| `Feather/Backend/Certificates/ODCertificateExport.swift` | `makeURL` gains an optional `provisionBase64` and substitutes `$(BASE64_PROVISION)` and `$(BASE64_PASSWORD)`; `$(PASSWORD)` and `$(BASE64_CERT)` are unchanged for existing consumers. New `requiresProvision(in:)`, `certificatePlaceholder` and `resolveTemplate(_:)` |
| `Feather/Utilities/FR.swift` | Export reads the profile when the template asks for it, refuses when it is missing, and reports a missing `.p12` instead of returning silently. New `passwordOpensKey(_:for:)` |
| `Feather/FeatherApp.swift` | Import handler rewritten: parse → stage → verify password → confirm → import → clean up |

**Why the password is not "guessed".** `passwordCandidates(from:declaredEncoding:)` returns the plausible readings in order (base64 first when undeclared, because that is what this app's importer documented; verbatim second), and the caller accepts a candidate **only when `p12_password_check` opens the key**. A wrong reading is rejected by the `.p12`, not by a heuristic, and every candidate failing produces `.passwordRejected`. `password_encoding=raw|base64` lets a producer state the intent explicitly.

**Structured errors.** `ODCertificateImportError` covers malformed link, unsupported link, missing/empty/invalid/oversized fields, rejected password, unreadable profile and staging failure. Messages name the *field*, never its value — the values are key material and a password.

**Export side.** The same double-decode existed on the way in: `_handleURL` took the value `URLComponents` had already decoded and decoded it again. A destination whose query contained `%` (for example `name=50%25off`) made `removingPercentEncoding` return `nil`, and the export simply did nothing. `ODCertificateExport.resolveTemplate` now uses the decoded value as-is, and only decodes a second time when the first value does not contain the certificate placeholder — which keeps working with callers that double-encode.

**What this does not do.** It does not validate the certificate chain or the profile's signature. Parsing succeeds ⇒ the bytes are well-formed base64, nothing more; trust decisions are unchanged (team/profile are shown in the confirmation, and revocation checking is the existing, separate OCSP path).

### L4 — key material moved out of the shared Documents tree

**Root cause.** `FileManager.certificates` pointed at `Documents/Certificates/<uuid>`. The app enables `UIFileSharingEnabled`, so that directory is browsable in Files and over Finder/iTunes; the files carried the default data-protection class and were included in iCloud/iTunes backups. Anyone with brief physical access, or a backup, could lift the signing identity.

**Fix — `Feather/Backend/Certificates/ODCertificateFiles.swift` (new).**

- Root is `Application Support/Odysseus/Certificates` (`FileManager.certificates` now returns it; `legacyCertificates` retains the old path). Application Support is not exposed by file sharing.
- `prepare()` runs once at launch from `AppDelegate`: creates the root, applies protection, migrates legacy material, re-applies protection to what is already stored.
- Protection = `isExcludedFromBackup` + `FileProtectionType.completeUntilFirstUserAuthentication` + owner-only POSIX permissions (`0700` directory, `0600` files). `completeUntilFirstUserAuthentication` rather than `complete` because an install can finish while the device is locked; a stricter class would break that read instead of protecting anything.
- Migration **moves** (never copies over) each safe child from `Documents/Certificates`, skips anything already present at the destination, and removes the legacy directory only when it is empty.
- `CertificateFileHandler.copy()` creates the directory and applies protection as part of the same `do` block; a partially copied directory is removed on failure.
- `deleteCertificate` and `CertificateFileHandler.cleanup()` go through `removeDirectory(for:)`, which rejects any name that is not a single path component and any URL that is not a direct child of the root.

**Behaviour change.** `CertificatesInfoView` had an "Open in Files" button that opened `Documents/Certificates/<uuid>`. That directory is deliberately no longer user-visible, so the button was removed rather than left pointing at nothing; exporting a certificate is the supported way to get the files out. `Documents/` itself remains shared (IPAs are still imported through it).

**What this does not do.** It does not encrypt the `.p12`; it relies on the platform's file protection. Files are unreadable while the device is locked before first unlock, readable after, and no longer leave the device in a backup. `UIFileSharingEnabled` stays on for the rest of the app's files.

### L5–L6 — temporary copies, and cleanup that cannot delete the wrong thing

**Root cause.** The import path called `FileManager.decodeAndWrite`, which writes to `temporaryDirectory/<uuid>.p12` and returns the URL. Nothing ever deleted them: not on success, not on the password failure, not on the early `return`s for malformed input. A plaintext copy of the private key accumulated in `/tmp` for the life of the container.

**Fix.** `ODCertificateFiles.writeTemporaryProtected` writes an app-owned, permission-restricted file; the import handler collects those URLs and deletes them in every exit path — parse failure, staging failure, unreadable profile, rejected password, confirmed import (success or failure) and Cancel. `removeTemporary` only removes files whose name carries the app's `OdysseusImport-` prefix **and** that live in the system temporary directory, so a document-picker URL can never be deleted by mistake.

### L7–L9 — install server: narrower bind, request guard, bounded lifetime

**Root cause.** `setupApp` bound `0.0.0.0`, so the listener answered on every interface — including cellular — for as long as it lived. The only control was the per-install route secret (added in Remediation 01). Lifetime was handled only on `.completed`/`.broken`; dismissing the sheet relied on `deinit`, and an install that never reached a terminal state left the listener up until the object died.

**Fix.**

| File | Change |
|---|---|
| `Feather/Backend/Server/ODInstallServerAccess.swift` *(new)* | `bindHost(...)` returns the address to bind — the **same** address written into the manifest URL; `isAcceptableRequest(...)` and `hostComponent(of:)` implement the request guard. Pure, and covered by tests |
| `Feather/Backend/Server/ServerInstaller+TLS.swift` | Binds `bindHost(...)` instead of `0.0.0.0` |
| `Feather/Backend/Server/ODInstallRouteSet.swift` | `route(for:)` resolves a path to one of five endpoints by exact match |
| `Feather/Backend/Server/ServerInstaller.swift` | Route handler is guard-then-switch; a request that fails the guard or matches no route gets the same `404`. `stop()` also fires 10 s after the payload is delivered, and a `maximumLifetime` (10 min) timer backs it up |
| `Feather/Views/Odysseus/Install/ODInstallSheet.swift`, `Feather/Views/Library/Install/InstallPreviewView.swift` | `installer.stop()` on `onDisappear` — dismissing the sheet is a cancellation |

**What the bind change achieves.** The listener now answers on exactly one address:

| Transport | Advertised host | Bound address |
|---|---|---|
| Semi Local (`serverMethod == 1`), `ipFix` off | device LAN IPv4 | that address |
| Semi Local, `ipFix` on | `127.0.0.1` | `127.0.0.1` |
| Fully Local TLS, identity hostname is an IPv4 literal | that literal | that literal |
| Fully Local TLS, hostname `localhost` | `localhost` | `127.0.0.1` |
| Fully Local TLS, hostname is a DNS name | the name | **`0.0.0.0`** — a name cannot be bound |

**What remains reachable.** LAN peers can still connect during an install window (that is the transport). They cannot enumerate paths: every endpoint is under a 128-bit secret and anything else 404s. Host validation blocks the browser/DNS-rebinding class of reach (a browser always sends `Host`); a host-less request is still served, because the secret is the credential and rejecting it would only risk breaking an install. The secret appears in the manifest URL by design, and is never logged.

**Verified without a device.** Bind selection, host parsing, method rejection and route scoping are unit-testable and are tested. That the listener actually accepts/rejects real sockets, and that iOS's installer is happy with the narrower bind, requires a device (see §7).

### L10–L13 — failures that looked like successes

| File | Root cause | Fix |
|---|---|---|
| `Feather/FeatherApp.swift` | A link could add an identity with no confirmation | The certificate is named (profile name, team) in an `Import Certificate?` alert; Cancel deletes the staged copies and stores nothing |
| `Feather/Views/Settings/Certificates/CertificatesAddView.swift` | Import completion ignored its error and dismissed; an unreadable profile was reported as "Bad Password" | Failure keeps the sheet open and shows the real error; the profile is validated before the password is judged |
| `Feather/Utilities/Handlers/CertificateFileHandler.swift` | `certNotValid` had no user-facing message | `LocalizedError` with an actionable message, plus `invalidDestination` |
| `Feather/Utilities/FR.swift` | Missing `.p12` returned silently | Explicit alert; export also refuses when the template needs a profile that does not exist |

---

## 4. Files changed

**Added (6)**

```
Feather/Backend/Certificates/ODCertificateFiles.swift
Feather/Backend/Certificates/ODCertificateImportLink.swift
Feather/Backend/Server/ODInstallServerAccess.swift
OdysseusTests/ODCertificateFilesTests.swift
OdysseusTests/ODCertificateImportLinkTests.swift
OdysseusTests/ODInstallServerAccessTests.swift
```

**Modified (14)**

```
Feather/Backend/Certificates/ODCertificateExport.swift
Feather/Backend/Server/ODInstallRouteSet.swift
Feather/Backend/Server/ServerInstaller.swift
Feather/Backend/Server/ServerInstaller+TLS.swift
Feather/Backend/Storage/Storage+Certificate.swift
Feather/Extensions/FileManager+documents.swift
Feather/FeatherApp.swift
Feather/Utilities/FR.swift
Feather/Utilities/Handlers/CertificateFileHandler.swift
Feather/Views/Library/Install/InstallPreviewView.swift
Feather/Views/Odysseus/Install/ODInstallSheet.swift
Feather/Views/Settings/Certificates/CertificatesAddView.swift
Feather/Views/Settings/Certificates/Info/CertificatesInfoView.swift
OdysseusTests/ODCertificateExportTests.swift
```

No dependency added, removed or re-pinned; no third-party code copied; no licence or notice touched. Both targets use `PBXFileSystemSynchronizedRootGroup`, so no project-file edit was needed.

---

## 5. Regression tests added

| File | Cases | Covers |
|---|---|---|
| `ODCertificateImportLinkTests.swift` | 18 | export → re-import round trip; reserved-character passwords; legacy raw-password template; candidate ordering and `password_encoding`; missing/empty/invalid/oversized fields; foreign scheme and host; double-encoded payload; messages never echo link contents |
| `ODCertificateFilesTests.swift` | 12 | storage root is outside `Documents`; legacy path distinct; name validation and traversal rejection; removal refuses unsafe names; missing directory reported; protection sets `0700`/`0600` and backup exclusion; temp cleanup removes only app-created files |
| `ODInstallServerAccessTests.swift` | 16 | bind selection for every transport; IPv4 validation; GET-only; host matching, case-insensitivity, port stripping, mismatch rejection, hostless allowance; route resolution with/without the secret; traversal and absolute paths do not resolve |
| `ODCertificateExportTests.swift` *(extended)* | +8 | `$(BASE64_PROVISION)` substitution; `$(BASE64_PASSWORD)` yields what the importer reads; `$(PASSWORD)` still raw for external consumers; `requiresProvision`; `resolveTemplate` keeps a `%`-bearing template intact and only decodes when the placeholder is missing |

**54 new cases; 98 in the suite.**

Not covered by tests, by nature: the biometric prompt, Vapor's socket behaviour, SQLite/Core Data, the keychain, and the iOS installer. Those need a device (§7).

---

## 6. Build and test results

| Command | Result |
|---|---|
| `swift --version` | **command not found** |
| `xcodebuild -version` | **command not found** |
| `git submodule status` | `IDeviceKitten`, `Zsign` unpopulated |
| `xcodebuild test -project Feather.xcodeproj -scheme Feather -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO` | **NOT RUN** |
| `git submodule update --init --recursive && make iphoneos` | **NOT RUN** |
| `scripts/verify_ipa.sh packages/Odysseus.ipa` | **NOT RUN** |
| Static checks in §1 | executed; results as listed |

**No test in this repository has been executed by this task.** Everything above marked fixed is a source-level claim awaiting the first CI build. The most likely compile-risk points are the `guard let` shorthand in `ODCertificateExport.makeURL`, the `switch` over `ODInstallRoute` inside the Vapor closure, and the alert action closures in `_handleCertificateImportURL`.

---

## 7. Remaining risks and required device checks

**Risks still open**

| Risk | Detail |
|---|---|
| TLS identity with a DNS name still binds `0.0.0.0` | A name cannot be bound. Mitigated by the 128-bit route secret and the request guard; documented in `ODInstallServerAccess` |
| Install server reachable on the LAN during an install | Required by the Semi Local transport; exposure is now one address, secret-scoped, GET-only, and time-bounded |
| `.p12` is protected but not encrypted by the app | Platform file protection + backup exclusion only; a jailbroken device or an unlocked-device forensic tool is out of scope, as in the audit |
| Legacy migration is unexercised | `prepare()` moves `Documents/Certificates/*`; a partial failure leaves material in place for the next launch and logs a code, but this has never run on a device |
| Third-party plist service receives the payload URL | `externalServerLink` posts `fetchurl=<payload url>` (which contains the secret) to `api.palera.in` or a custom server when that mode is chosen. Unchanged by this task, recorded in Remediation 01 |
| Import still accepts a certificate the user cannot verify | The confirmation names the profile and team; the certificate chain is not validated by the importer (unchanged, out of scope) |
| `try!` in `ServerInstaller.env` and `as!` in `ODX509` remain | Verified present, not addressed |

**Device / local-network checks still required**

1. **Migration:** install over a build that already has a certificate, launch, sign an app — the certificate must still be found (proves the move worked). Then confirm `Documents/Certificates` is gone and `Application Support/Odysseus/Certificates` holds the material with `0600`.
2. **No backup:** back up to a Mac/iCloud and confirm the certificate directory is not in the backup.
3. **Round trip:** export with an `odysseus://import-certificate?...&password=$(BASE64_PASSWORD)&mobileprovision=$(BASE64_PROVISION)` template, open the link, confirm the dialog, and sign with the imported certificate. Repeat with Cancel — nothing may be added. Repeat with a wrong password — the alert must say the password failed.
4. **Install, Semi Local (both `ipFix` states) and Fully Local TLS:** the manifest must load and the app install. This is the highest-risk change: it exercises the narrower bind and the `Host` guard.
5. **Reachability:** from another host on the LAN, `curl` the payload path without the secret (must 404) and with it (must succeed) while an install is running; after the install completes, both must fail to connect.
6. **Lifetime:** start an install, dismiss the sheet, and confirm the port closes within seconds; leave an install untouched and confirm the 10-minute cap closes it.
7. **Lock-screen install:** start an install, lock the device — the payload read must still succeed under `completeUntilFirstUserAuthentication`.

---

## 8. Recommended next task

1. **Signing verification depth (`ODY-201`)** — the pipeline still checks that a signature exists rather than what it covers. This is the largest remaining gap between "signed" and "verified".
2. **`ODY-BUG-005` background-task registration** — still invalid on launch; needs a device test to confirm.
3. **Dependency pinning and notices (`L-01`/`L-02`)** — mechanical, release-blocking for distribution.

Do not start feature work until this remediation is reviewed and the device checks above have been run.
