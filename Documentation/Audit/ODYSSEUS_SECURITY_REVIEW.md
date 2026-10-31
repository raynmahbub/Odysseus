# Odysseus security review

**Audit date:** 2026-10-31 · **Revision:** `6ee21d6` · **Type:** static review (no device, no dynamic instrumentation, no fuzzing)
**Companion:** `ODYSSEUS_BUG_AND_RELIABILITY_AUDIT.md` (defects), `UPSTREAM_LICENSE_AUDIT.md` (provenance).

## 1. What is being protected

| Asset | Where it lives today | Consequence of compromise |
|---|---|---|
| Signing private key + password | `.p12` in `Documents/Feather/Certificates/<UUID>/`, password as a plain Core Data attribute | attacker can sign apps the user will install; identity theft of the developer account |
| Apple ID credentials | keychain via `ODKeychain` (`AfterFirstUnlockThisDeviceOnly`), plus anisette material in the app container | account takeover, 2FA bypass via anisette |
| Provisioning profiles / UDIDs | same certificate directory | device inventory disclosure |
| Downloaded/signed IPAs | `Documents/…`, `Library/…`, temp dirs | disclosure of pre-release builds |
| Install server | Vapor, `0.0.0.0:<random 4000–8000>` | local-network exposure of manifests and payloads |
| Deep-link surface | `odysseus://` with six handlers | unsolicited imports, installs, and credential export |

## 2. Threat model

| # | Adversary | Capability | Entry point |
|---|---|---|---|
| T1 | Another app on the device | can open `odysseus://` URLs (any app may) | deep-link handlers |
| T2 | Web page / QR code | can link to `odysseus://` | deep links |
| T3 | Local network peer | can reach the install server while it runs | HTTP/HTTPS server |
| T4 | Malicious or compromised source | controls IPA bytes and metadata | download → import → extract |
| T5 | Malicious IPA author | controls archive structure and Mach-O | extraction, signing |
| T6 | Person with brief physical access | can open the app, read exported files | UI, Files app (file sharing is on) |
| T7 | Supply chain | controls dependency code | SPM resolution |

Out of scope: jailbroken devices, kernel exploits, Apple platform compromise, and remote attackers with no local presence or link.

---

## 3. Findings

### S-01 — Certificate export sends the `.p12` **and its raw password** to a caller-supplied URL, without biometric confirmation
- **Severity:** High · **Threat:** T1/T2/T6 · **Status:** confirmed in source
- **Evidence:** `FR.swift:164–223` — `exportCertificateAndOpenUrl(using: template)` substitutes the certificate (percent-encoded) and `certificate.password` **raw** into an arbitrary template and calls `UIApplication.shared.open`; reachable from `odysseus://export-certificate?callback_template=<any URL>` (`FeatherApp.swift:146–157`). The confirmation alert (`FR.swift:214–219`) warns that an external app will be able to sign, but **never displays the destination**.
- **Impact:** any app or web link can present the export dialog; a single tap sends the private key to an attacker-controlled scheme or `https` host. The password is unencoded, so reserved characters both break the transfer and end up in cleartext in URL logs/history. The same passwords are the ones stored in Core Data. That the exporter writes the password raw while the app's own importer expects base64 (see ODY-BUG-001) shows the round trip was never tested — so the export path is being exercised almost exclusively by external consumers, which is exactly the wrong population to trust.
- **Fix:** require Face ID/passcode; show the resolved destination host/scheme in the confirmation; refuse non-`odysseus`-registered destinations unless the user types them; percent-encode the password **and** prefer a file/share-sheet transfer over URLs entirely.
- **Acceptance:** export without a successful biometric evaluation cannot occur; the confirmation names the destination; D-12 round-trips hostile passwords.

### S-02 — Certificate import is silent: no confirmation, no authentication, and it can become the default identity
- **Severity:** High · **Threat:** T1/T2 · **Status:** confirmed in source
- **Evidence:** `FeatherApp.swift:97–144` decodes `p12`/`mobileprovision`/`password` from the URL and calls `FR.handleCertificateFiles(...)` with no prompt. `ODSignPipeline.defaultCertificate` (`:98–102`) falls back to `certificates.first` when no default is set.
- **Impact:** a link can install an attacker's signing identity on the device without the user seeing anything beyond an alert on success; if the user had no certificate, the next install is signed with it. The user believes they signed with their own identity.
- **Fix:** require explicit confirmation naming the certificate subject/team and the source; never auto-select a non-user-confirmed certificate as default; require the device to be unlocked (already implied by keychain class, not by the flow); log the import in diagnostics.
- **Acceptance:** import requires a user gesture on a named certificate; `defaultCertificate` never returns an identity the user has not confirmed.

### S-03 — Certificate material at rest is unprotected, and `Documents/` is user-visible
- **Severity:** High · **Threat:** T6 · **Status:** confirmed in source
- **Evidence:** `Storage+Certificate.swift:30` (`password` plain attribute), `CertificateFileHandler.copy()` (`:47–59`, copies into `Documents/Feather/Certificates/<UUID>/` with the default protection class and no `isExcludedFromBackup`), `Info.plist:106` `UIFileSharingEnabled = true`. Contrast `ODLocalServerTLS.swift:102–106, 228–232`, which correctly applies `0o700`/`0o600`, protection and backup exclusion to *its* identity — the pattern exists in this codebase, it was simply not applied to the user's certificate store.
- **Impact:** the private key and its password are readable by anyone who can browse Files/iTunes file sharing, and both are included in device backups (so they travel to iCloud and to any computer that restores the backup). File protection is whatever the class default is — on a locked device after first unlock, that is not sufficient for key material.
- **Fix:** keychain for the password (roadmap ODY-102), `completeUntilFirstUserAuthentication` + `isExcludedFromBackup` on the directory, and stop exposing `Documents/` (move to `Application Support` with file sharing disabled, or expose only an explicitly shared folder).
- **Acceptance:** password absent from the Core Data store after migration; directory attributes verified; Files app shows no certificate material.

### S-04 — The install server listens on all interfaces with no authentication
- **Severity:** Medium · **Threat:** T3 · **Status:** confirmed in source
- **Evidence:** `ServerInstaller+TLS.swift:36` (`.hostname("0.0.0.0", port:)`), `ServerInstaller.swift:79–110` (four routes: manifest plist, two icons, payload), no token, no per-session secret, no rate limit; port is random per launch (`ServerInstaller.swift:25`), which is obscurity, not control.
- **Impact:** while an install is in progress, any host on the same network can fetch the manifest and the IPA payload, learning bundle id, name, and the binary itself. The random port narrows the window but is enumerable.
- **Fix:** bind loopback unless the selected transport requires LAN; add a per-install random path token; stop the server immediately after the install completes (already attempted — verify `_shutdownServer`), and surface a LAN-mode warning.
- **Acceptance:** D-01/D-02 pass with the server bound to loopback; a second device on the LAN cannot fetch the payload.

### S-05 — Archive extraction trusts the archive
- **Severity:** Medium · **Threat:** T4/T5 · **Status:** confirmed in source (library behaviour unverified)
- **Evidence:** `AppFileHandler.extract()` calls `Zip.unzipFile(..., password: nil)` with no entry-count, expanded-size, ratio, or path validation; `.deb` extraction (`TweakHandler` → `AR` + `extractFile`) likewise.
- **Impact:** a crafted IPA can fill the device's storage (denial of service), or — if the extraction library does not normalise paths — write outside the temp directory. The second part depends on `marmelroy/Zip` internals, which were not executed or fuzzed here.
- **Fix:** validate entries before extraction (absolute paths, `..`, symlinks, count, size, ratio); extract into a fresh directory and verify containment afterwards.
- **Acceptance:** `zipbomb.ipa` and `traversal.zip` fixtures are rejected with no writes outside the sandbox.

### S-06 — OCSP responses are replayed-able and cached for an hour
- **Severity:** Medium · **Threat:** T4 (revoked certificate kept usable) · **Status:** confirmed in source
- **Evidence:** `ODOCSPChecker` builds requests without a nonce and `ODCertificateStatusStore.isFresh(maximumAge: 3600)` makes a result authoritative for an hour; `ODSignPipeline._freshResult` reuses it.
- **Impact:** a revoked certificate that was "good" when last checked can continue signing for up to an hour even with network available; an attacker able to influence the network can replay an old "good" response within that window (signature verification cannot distinguish a replay).
- **Fix:** include a nonce and verify it; reduce the cache for the *pre-signing* decision (e.g. 5 minutes) while keeping a longer cache for display; record the check time in the signing diagnostics.
- **Acceptance:** D-05 rejects a revoked certificate immediately after revocation; a nonce mismatch invalidates a response.

### S-07 — Under "Block", an unverifiable revocation status still signs
- **Severity:** Medium · **Threat:** policy · **Status:** confirmed in source
- **Evidence:** `ODSignPipeline._revocationGate` (`:389–409`) returns early unless `result.status == .revoked`.
- **Impact:** a user who chose "Block" expects refusal unless the certificate is proven good; airplane mode or an OCSP outage defeats the control.
- **Fix:** make `.block` mean "refuse unless verified good" and offer an explicit one-time override.
- **Acceptance:** D-06 matches the documented policy.

### S-08 — Dependencies are unpinned, including three AGPL packages on moving branches
- **Severity:** Medium · **Threat:** T7 · **Status:** confirmed `SideSign/Package.swift:33–38`; no root `Package.resolved`
- **Impact:** a compromised or simply changed upstream silently enters the next build; the licence of the shipped binary can change between two identical commits.
- **Fix:** pin by revision, commit lockfiles, enable Dependabot, and review diffs before bumping (roadmap ODY-006 / licence L-02).

### S-09 — Keychain failures are swallowed
- **Severity:** Medium · **Threat:** integrity of the credential store · **Status:** confirmed in source
- **Evidence:** `ODKeychain.swift` ignores every `OSStatus`.
- **Impact:** the app can believe a password was stored when it was not; the user's later sign-in failures are unexplainable, and a failed delete can leave stale credentials behind.
- **Fix:** typed errors, surfaced to the UI; keep the "remember password" toggle honest.

### S-10 — Private API used for device identification
- **Severity:** Low · **Threat:** policy (App Review / platform) · **Status:** confirmed in source
- **Evidence:** `Feather/Utilities/MobileGestalt.swift:11–15` (`dlopen`/`dlsym` of `libMobileGestalt.dylib`, `MGCopyAnswer`), used only by `ODDiagnosticsView.swift:26`.
- **Impact:** guaranteed App Store rejection; no user harm. The app is distributed outside the store, but the pattern is unnecessary.
- **Fix:** replace with `sysctlbyname("hw.machine")` or `UIDevice.current.model` — public API, same value for diagnostics.

### S-11 — Log privacy annotations are absent
- **Severity:** Low · **Threat:** T6 (diagnostics export) · **Status:** confirmed by search (0 `privacy:` uses)
- **Impact:** no secrets are currently logged (verified), but the absence of annotations means any future interpolation of a token, email, or identifier into an OSLog message would be recorded unredacted when a debugger is attached, and exported by `ODDiagnosticsView`.
- **Fix:** adopt `privacy: .private` by default in `Logger++` helpers; add a redaction test.

### S-12 — The `install/` deep link starts an unsolicited download
- **Severity:** Low · **Threat:** T1/T2 · **Status:** confirmed in source
- **Evidence:** `FeatherApp.swift:164–171` (`odysseus://install/<url>` → `DownloadManager.startDownload`), no confirmation.
- **Impact:** an unsolicited download consumes storage and appears in the library; it is not signed or installed without further user action.
- **Fix:** confirm before downloading; validate scheme is `https` and host is on an allow-list or a known source.

### S-13 — Certificate deletion does not guarantee removal (cross-ref ODY-BUG-006)
- **Severity:** Medium · **Threat:** T6 · **Status:** confirmed in source
- **Evidence:** `Storage+Certificate.swift:46–52`.
- **Impact:** a compromised certificate the user deleted can remain on disk indefinitely; combined with S-03 that material is readable.
- **Fix:** quarantine-or-fail semantics; overwrite/remove the directory; report failures.

---

## 4. Positive controls (verified, keep them)

| Control | Evidence |
|---|---|
| OCSP responses are cryptographically verified: issuer signature, responder ID, `id-kp-OCSPSigning` EKU, key-usage, Apple trust anchor, freshness | `ODOCSPChecker`, `ODX509`, `ODDER`; 7 unit tests |
| Local TLS identity is user-owned, generated per device, `0o700`/`0o600`, `completeFileProtection`; no bundled shared key; server refuses to start without it | `ODLocalServerTLS`, `ServerInstaller+TLS` |
| Apple ID secrets are in the keychain, not Core Data | `ODKeychain` |
| Delete-with-restore prevents data loss on partial deletes | `Storage+Shared._deleteRecord`, unit test |
| No secrets in logs; no `print` of credentials | grep audit |
| ATS is not globally disabled; exceptions are limited to Apple's HTTP CRL/OCSP/CA endpoints, which require HTTP | `Info.plist:71–99` |
| App entitlements are minimal (`get-task-allow` only) | `Feather.entitlements` |
| No `DispatchQueue.main.sync`; no unsafe global mutable state in ObjC | grep audit |
| Quarantine + snapshot discipline bound the blast radius of a failed import | `ODSignPipeline`, `Storage` |

---

## 5. Accepted risks (with rationale)

| Risk | Why accepted | Revisit when |
|---|---|---|
| ATS exceptions for `certs.apple.com`, `crl.apple.com`, `ocsp.apple.com` | Those endpoints are HTTP-only; responses are signed and verified, so a MITM cannot forge a status (only replay — see S-06) | Apple moves them to HTTPS |
| OCSP "unknown" does not block under `.block` | Matches "cannot determine" semantics in the original design | User research shows otherwise, or S-07 is fixed |
| No jailbreak/tamper detection | Out of scope for a sideloading tool that runs on stock iOS | — |
| App is not notarised / store-distributed | Product decision; CI builds and ad-hoc signs | Distribution change |
| `DefaultSourcesInstaller` supports a `remoteList` fetched on every launch | The mechanism exists but the bundled config still contains the `ADD_HERE_REMOTE_LIST_URL` placeholder, so it is inert; `fastsign.dev`, `apptesters.org` and `ipa.cypwn.xyz` are added unconditionally on first launch | Setting a real `remoteList` — it becomes a remote-control channel over which sources are added; treat it as a security decision, not a convenience |
| Default third-party sources are installed on first launch | Product decision; documented in `DefaultSources.json` | A user-visible, opt-in source picker replaces it |

---

## 6. Remediation and release gate

| Finding | Roadmap task | Phase |
|---|---|---|
| S-01, S-13 | ODY-001, ODY-102 | 0–1 |
| S-02 | ODY-001 (deep-link hardening) | 0 |
| S-03 | ODY-102 | 1 |
| S-04 | ODY-005, ODY-203 | 0, 2 |
| S-05 | ODY-104 | 1 |
| S-06, S-07 | ODY-103 (pipeline policy), follow-up on OCSP nonce | 1 |
| S-08 | ODY-006 | 0 |
| S-09, S-11, S-12 | ODY-003, ODY-004, ODY-101 | 0–1 |
| S-10 | ODY-003 (replace with public API) | 0 |

**Release gate — a build may not be distributed while any of these is true:**

1. A certificate export can happen without a biometric/passcode check (S-01).
2. A `odysseus://` link can import a certificate without a named, confirmed user action (S-02).
3. A certificate password exists in the Core Data store or the p12 directory is unprotected (S-03).
4. A dependency resolves from a branch (S-08).
5. `NSLocalNetworkUsageDescription` is missing while the server binds `0.0.0.0` (S-04).
6. Any `try!`/`as!` remains on an input-derived path (crash → potential data loss).

**Verification status:** every finding above is static. No exploit was attempted, no dynamic analysis was performed, and no finding has been reproduced on a device. S-05 in particular depends on third-party decompression behaviour that was not executed.
