# Odysseus bug and reliability audit

**Audit date:** 2026-10-31 · **Revision:** `6ee21d6` · **Method:** static trace of every error path in the acquire → import → sign → install chain, plus every `try!`, `as!`, `try?`, `print(` and ignored return value.

**Two separate lists follow.** §1 contains defects whose failure mode is *provable from the code path* (no device needed to see that the state machine cannot recover). §2 contains defects that depend on runtime conditions — they are plausible and worth fixing, but they are not presented as observed failures. Nothing in either list has been reproduced on hardware: **no device or simulator was available** (see `BASELINE_AUDIT.md` §7).

Severity: **Critical** = data/credential loss or silent corruption · **High** = the feature cannot complete, or a stuck state with no recovery · **Medium** = wrong result or misleading feedback · **Low** = maintenance/quality.

---

## 1. Confirmed defects (provable from the code path)

### ODY-BUG-001 — Certificate export writes an unencoded password into a URL
- **Severity:** High · **Area:** certificates · **Status:** confirmed in source
- **Files:** `Feather/Utilities/FR.swift:164–223` (template substitution at `:185`, `UIApplication.open` at `:189`), consumed by `Feather/FeatherApp.swift:97–144` and `Feather/Views/Settings/SettingsView.swift:220–231`
- **Root cause:** the export takes a caller-supplied template (documented example: `livecontainer://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)`) and substitutes both values by string interpolation (`:183–185`). The certificate is percent-encoded; the password is not encoded at all.
- **Impact:** any password containing `&`, `+`, `#`, `%`, `?` or a space truncates or corrupts the import on the receiving side — the exported backup silently fails to restore. There is a second, independent defect on the same path: the exporter writes the password **raw**, while Odysseus's own importer (`FeatherApp.swift:104–108`) expects it **base64-encoded**, so exporting from Odysseus and importing back into Odysseus cannot work for any password. The template comment (`FeatherApp.swift:148–150`) documents the raw-password form because the feature was built for LiveContainer's importer, not this app's. Independently, the credential is exposed in a URL (see `ODYSSEUS_SECURITY_REVIEW.md` S-01/S-02).
- **Fix:** build the URL with `URLComponents` + `percentEncodedQueryItems`; cap total URL length (base64 of a 5–10 KB `.p12` already strains `openURL`); if the length cap is exceeded, hand the file to the share sheet instead of a URL; require Face ID before export.
- **Regression test:** `CertificateExportURLTests.testPasswordsWithReservedCharactersRoundTrip` — encode, parse with the same code the import path uses, assert the recovered password equals the original, for a table of `p@ss&word`, `a+b`, `50%off`, `has space`, `p#1?`; plus `testExportedURLIsAcceptedByOwnImporter`.

### ODY-BUG-002 — A failed import leaves the download row stuck forever
- **Severity:** High · **Area:** downloads · **Status:** confirmed in source
- **File:** `Feather/Backend/Observable/DownloadManager.swift:199–219` (catch at `:216–218`)
- **Root cause:** inside `urlSession(_:downloadTask:didFinishDownloadingTo:)` the create/move/import sequence is wrapped in `do/catch`, and the `catch` only calls `print`. The `Download` object is not removed from `downloads`, `ODSignPipeline.downloadEnded` is not called, and no failure is published.
- **Impact:** a disk-full device, a filename collision, or a sandbox write error leaves a permanently "downloading" library row; the user cannot cancel it into a clean state, retry, or see why. `ODSignPipeline._pendingGets` also keeps the id, so the same app cannot be re-fetched.
- **Fix:** in the `catch`: remove the download, call `downloadEnded(id)`, publish a typed failure (`ODSignError.importFailed(reason:)`), and delete the partial file.
- **Regression test:** `DownloadFailureTests.testImportThrowClearsRowAndPublishesFailure` — inject a throw via a `DownloadService` seam (requires M1 from the architecture audit) and assert `downloads.isEmpty`, `phases[id]` is `.failed`, and the temp file is gone.

### ODY-BUG-003 — Import errors are reported as "Download failed"
- **Severity:** Medium · **Area:** downloads/pipeline · **Status:** confirmed in source
- **Files:** `DownloadManager.swift:171–197` (`err` only triggers a haptic), `ODSignPipeline.swift:346–358`
- **Root cause:** `FR.handlePackageFile`'s completion error is discarded; `downloadEnded` then sees no download and, after 3 s, publishes the generic `.failed("Download failed")`.
- **Impact:** the most common user-visible failure (a corrupt or password-protected IPA) is attributed to the network, so users retry downloads instead of fixing the file, and diagnostics cannot distinguish the two cases.
- **Fix:** propagate the import error into the pipeline and map it to a specific message (`unreadable archive`, `wrong password`, `not an IPA`).
- **Regression test:** `ImportErrorMappingTests` over a table of `SigningFileHandlerError` values.

### ODY-BUG-004 — The 3-second download-end timer can cancel a slow import
- **Severity:** Medium · **Area:** downloads/pipeline · **Status:** confirmed by code logic; not reproduced
- **File:** `ODSignPipeline.swift:346–358`; competing path `:360–377`
- **Root cause:** `downloadEnded` waits 3 s and then marks the phase failed if it is still `.downloading`. `_didImport` begins with `guard _pendingGets.remove(downloadID) != nil else { return }`. If the import takes longer than 3 s (a 1–2 GB IPA, or a busy device), the timer removes `_pendingGets`, so the late import notification is **discarded**.
- **Impact:** the app is imported into the library but never signed; the UI says "Download failed"; the user retries and ends up with a duplicate import.
- **Fix:** replace the timer with an explicit terminal event from the import stage (success or failure), and make `_didImport` tolerant of a cleared `_pendingGets` (recover by matching `uuid`).
- **Regression test:** `SlowImportTests.testImportCompletingAfterGraceStillSigns` with a 5 s artificial delay in the import seam.

### ODY-BUG-005 — Background task identifiers are registered after launch
- **Severity:** High (crash or silent task loss) · **Area:** background execution · **Status:** confirmed in source
- **File:** `Feather/Utilities/BackgroundTaskManager.swift:24–46`; call sites `DownloadManager.swift` (`startTask`), guarded by `#available(iOS 26.0, *)`
- **Root cause:** `BGTaskScheduler.shared.register(forTaskWithIdentifier:using:launchHandler:)` is called with a **per-download** identifier at the moment a download starts. Apple requires every launch handler to be registered before the app finishes launching, and the identifier must be listed in `BGTaskSchedulerPermittedIdentifiers`.
- **Impact:** depending on OS version, this either throws an uncatchable `NSInternalInconsistencyException` (crash when starting a download) or silently never runs. Neither outcome is acceptable for the primary path of the app.
- **Fix:** register a single fixed identifier in `Info.plist` at `didFinishLaunching`, and carry the active download id in `UserDefaults`/the task's user-info rather than in the identifier. If per-download continuation is genuinely required, keep the dynamic registration but wrap it behind a feature flag **and** verify on device first.
- **Regression test:** none possible off-device. Add a launch-time assertion test that every identifier passed to `register` appears in `Info.plist`'s `BGTaskSchedulerPermittedIdentifiers`.

### ODY-BUG-006 — Deleting a certificate can silently leave the private key on disk
- **Severity:** Medium (security-relevant) · **Area:** certificates · **Status:** confirmed in source
- **File:** `Feather/Backend/Storage/Storage+Certificate.swift:46–52`
- **Root cause:** `try? FileManager.default.removeItem(at: url)` swallows the failure and the Core Data record is deleted regardless.
- **Impact:** an orphaned `.p12` remains in `Documents/Feather/Certificates/<UUID>/` after the user "deletes" a compromised certificate — exactly when deletion matters.
- **Fix:** reuse the quarantine pattern from `Storage+Shared._deleteRecord`; if the file cannot be moved aside, keep the record and report.
- **Regression test:** `CertificateDeleteTests.testFileRemovalFailureKeepsRecord` with an injected file manager that throws.

### ODY-BUG-007 — Keychain failures are invisible
- **Severity:** Medium · **Area:** Apple ID · **Status:** confirmed in source
- **File:** `Feather/Backend/AppleID/ODKeychain.swift` (`SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete` return values unused)
- **Root cause:** every `SecItem*` status is discarded.
- **Impact:** "Remember password" can appear enabled while nothing was stored; a locked keychain (`AfterFirstUnlock` before first unlock) returns `errSecInteractionNotAllowed` and the sign-in fails later, apparently without cause.
- **Fix:** return typed errors (`ODKeychainError.status(OSStatus)`), surface the first failure in `ODAppleIDView`, and stop reporting success on a failed write.
- **Regression test:** `KeychainErrorTests` against an injected `SecItem` shim.

### ODY-BUG-008 — `try!` in the `.deb` reader
- **Severity:** Medium · **Area:** tweak injection · **Status:** confirmed in source
- **File:** `Feather/Utilities/ARDecompression/AR.swift:14`
- **Root cause:** `try!` on a file-handle read while parsing the `ar` header of a `.deb`.
- **Impact:** a truncated or non-`ar` file selected as a tweak crashes the app instead of reporting a bad tweak.
- **Fix:** `throws` + a user-facing "this .deb is not readable".
- **Regression test:** `ARDebParseTests.testTruncatedArchiveThrows` with a 12-byte fixture.

### ODY-BUG-009 — `try!` in the local TLS setup
- **Severity:** Medium · **Area:** install server · **Status:** confirmed in source
- **File:** `Feather/Backend/Server/ServerInstaller+TLS.swift:19–20`
- **Root cause:** `try!` on environment/host resolution during server start.
- **Impact:** a misconfigured network environment crashes during install rather than falling back to the semi-local transport with a clear message.
- **Fix:** propagate the error; the call site already reports transport failures.
- **Regression test:** `LocalServerTests.testInvalidInterfaceReportsInsteadOfTrapping`.

### ODY-BUG-010 — Forced `SecIdentity` cast during OCSP
- **Severity:** Medium · **Area:** revocation · **Status:** confirmed in source
- **File:** `Feather/Backend/Certificates/ODX509.swift:172`
- **Root cause:** `as! SecIdentity` after a query that can return a partially-matching item.
- **Impact:** a malformed or half-imported certificate crashes during a status check — one of the few paths a user can trigger by importing a bad file.
- **Fix:** `guard let identity = … as? SecIdentity else { throw ODX509Error.notAnIdentity }`.
- **Regression test:** `ODX509Tests.testNonIdentityItemThrows` (the test target already links the app, so the type is reachable).

### ODY-BUG-011 — Pull-to-refresh is silently dropped while a refresh is running
- **Severity:** Low · **Area:** sources · **Status:** confirmed in source
- **File:** `Feather/Views/Sources/SourcesViewModel.swift:34` (`guard isFinished else { return }`)
- **Root cause:** concurrency guard returns instead of coalescing.
- **Impact:** a user who pulls to refresh during the automatic refresh gets no result and no feedback; the refresh control snaps back.
- **Fix:** set a `pendingRefresh` flag and re-run on completion.
- **Regression test:** `SourceRefreshTests.testSecondRefreshWhileRunningRunsAfterFirst`.

### ODY-BUG-012 — Download failures carry no reason and cannot be retried
- **Severity:** Low · **Area:** downloads · **Status:** confirmed in source
- **File:** `DownloadManager.swift:239–257`
- **Root cause:** `didCompleteWithError` removes the row and calls `downloadedEnded`; the `Error` is discarded.
- **Impact:** every network failure shows "Download failed" after 3 s; no reason, no retry button, no resume offer even though `resumeData` is supported elsewhere.
- **Fix:** forward the error, offer retry with `resumeDownload`.
- **Regression test:** `DownloadErrorPresentationTests`.

### ODY-BUG-013 — Background audio engine gains a node per start
- **Severity:** Low · **Area:** background execution · **Status:** confirmed in source
- **File:** `Feather/Utilities/BackgroundAudioManager.swift:19–40` (`_engine.attach(silence)` at `:33`)
- **Root cause:** `start()` attaches a fresh player node every call and never detaches.
- **Impact:** repeated download start/stop grows the engine graph; eventual audio-session glitches and wasted memory.
- **Fix:** create the node once; guard `start()` on `!node.isPlaying`; detach in `stop()`.
- **Regression test:** `BackgroundAudioTests.testStartTwiceAttachesOnce` (requires extracting the engine behind a protocol).

### ODY-BUG-014 — Local-network permission string is missing
- **Severity:** Medium · **Area:** install · **Status:** confirmed in source
- **Files:** `Feather/Resources/Info.plist` (no `NSLocalNetworkUsageDescription`, no `NSBonjourServices`), `Feather/Backend/Server/ServerInstaller+TLS.swift:36` (binds `0.0.0.0`)
- **Root cause:** the server listens on all interfaces but the manifest declares no local-network purpose string.
- **Impact:** on iOS 14+ any LAN access triggers the local-network prompt with no explanation text; behaviour of the install flow when the user declines is unhandled (the device may still reach loopback, so the failure can appear as a generic install error).
- **Fix:** add `NSLocalNetworkUsageDescription`; bind `127.0.0.1` when the intended transport is loopback-only; handle the denial case explicitly.
- **Regression test:** plist lint test asserting required keys exist for each server transport.

### ODY-BUG-015 — Download-origin list grows without bound in `UserDefaults`
- **Severity:** Low · **Area:** library · **Status:** confirmed in source
- **File:** `Feather/Backend/Odysseus/ODSignPipeline.swift:427–440`
- **Root cause:** every download UUID is appended to a `UserDefaults` array and never pruned.
- **Impact:** slow start-up and a permanent record of every download after months of use; the value is also duplicated data that the Core Data `Downloaded` entity already holds.
- **Fix:** query `Downloaded` (or a stored flag) instead.
- **Regression test:** `LibraryOriginTests.testOriginDerivedFromStore`.

### ODY-BUG-016 — `print` bypasses the diagnostics pipeline
- **Severity:** Low · **Area:** diagnostics · **Status:** confirmed in source
- **Files:** `DownloadManager.swift:217`, `BackgroundAudioManager.swift:37`, `BackgroundTaskManager.swift:46`
- **Impact:** the one error message that explains BUG-002 is invisible to `ODDiagnosticsView`, which exports `OSLog` only. The export claims to help diagnose failures it cannot see.
- **Fix:** replace with `Logger.misc.error`, then delete the prints.
- **Regression test:** CI grep that fails the build on `print(` outside tests.

### ODY-BUG-017 — Dead code and a dead signing option
- **Severity:** Low · **Area:** whole app · **Status:** confirmed in source
- **Files:** `Feather/Views/Download/DownloadHeaderView.swift`, `Feather/Views/Common/FRExpirationPillView.swift`, `Feather/Views/Common/FlexibleHeader.swift` (no references outside their own file, after manual confirmation that `FlexibleHeader`'s `.flexibleHeaderContent()` modifier *is* used in `SourceAppsDetailView.swift:32`); `Options.dynamicProtection` (`OptionsManager.swift:77,135`) is never read.
- **Impact:** 51 of 185 type declarations are unreferenced outside their own file; readers cannot tell live code from abandoned code, and the dead toggle implies a capability that does not exist.
- **Fix:** delete the three files and the unused option after a reference audit (M4 in the architecture audit).
- **Regression test:** none; verified by build.

---

## 2. Theoretical / conditional defects

These are not proven failures. Each names the condition under which it becomes one.

| ID | Severity if triggered | Defect | Condition | Where |
|---|---|---|---|---|
| T-01 | High (policy) | Under the **Block** revocation policy, a certificate whose status is *unknown* (`couldntCheck`: no network, OCSP timeout) is **not** blocked — the gate only throws on `.revoked` | User expects "block" to mean "refuse unless proven good" | `ODSignPipeline.swift:389–409` |
| T-02 | Medium | OCSP requests carry no nonce, and results are cached for up to 3600 s; a replayed "good" response is accepted | A revoked certificate checked < 1 h ago still signs | `ODOCSPChecker.swift`, `ODCertificateStatusStore.isFresh` |
| T-03 | Medium | Signing cannot be cancelled: `Task` cancellation does not reach `Zsign.sign` | User backs out of a 2 GB sign; work continues and later installs a stale artefact | `SigningHandler`/`ZsignHandler` |
| T-04 | Low | Provisioning-profile expiry is compared against the device clock | User changes the date to bypass expiry messaging | `CertificateReader`, `ODExpiryPill` |
| T-05 | Medium | A very large source JSON is decoded entirely in memory | A hostile or broken source with 100k apps | `SourcesViewModel.fetchSources` |
| T-06 | Medium | Importing the same IPA twice creates two rows | No uniqueness constraint on `uuid`/bundle id | `AppFileHandler.addToDatabase` |
| T-07 | Medium | `Zip.unzipFile` is used with no entry-count, expanded-size, or path check | Malicious IPA (zip bomb, `../` entries) | `AppFileHandler.extract()` — see S-06 |
| T-08 | Low | p12 password is a plain Core Data attribute, so it is included in any store backup | Device backup / iCloud backup restored elsewhere | `Storage+Certificate.swift:30` |

---

## 3. Fix order (feeds the roadmap)

| Order | Bugs | Why first |
|---|---|---|
| 1 | 001, 002, 005, 014 | Credential handling and the two ways the primary pipeline can dead-end or crash |
| 2 | 003, 004, 006, 007 | Correctness of failure reporting; a user must be able to tell what happened |
| 3 | 008, 009, 010 | Crash-on-bad-input sites; each is a one-line change with an obvious test |
| 4 | 011–017 | Quality; batch with the migration steps M2–M4 |

---

## 4. What was checked and found clean

Recorded so it is not re-audited:

- No `DispatchQueue.main.sync` anywhere.
- No secrets written to `OSLog`, `print`, or diagnostics (grep for password/token in log statements: none).
- Delete-with-restore is correct in `Storage+Shared._deleteRecord` and unit-tested.
- `@unchecked Sendable` appears twice (`DownloadManager`, `AppFileHandler`) and both are narrow, documented uses.
- Retain-cycle scan of closures capturing `self` in long-lived managers found no cycle.
- `ODOCSPChecker` verifies signature, responder authorisation, Apple trust anchor and freshness before trusting a response.
- The local TLS identity is generated per device with `0o700`/`0o600` and `completeFileProtection`; the server refuses to start without it.
