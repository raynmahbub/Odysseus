# Odysseus testing strategy

**Audit date:** 2026-10-31 · **Revision:** `6ee21d6`

## 0. The honest starting point

- **16 XCTest cases in 6 files**, all passing in CI (run `41198043032`).
- They cover **four** capabilities out of 118 in the feature matrix: OCSP parsing/freshness/authorisation, Zsign outcome evaluation, storage concurrency, and Apple-ID material cleanup.
- **Nothing that requires a device has ever been verified** — not signing, not installing, not Apple ID sign-in, not background downloads, not the local TLS server.
- Consequences of the missing seams: `FR`, `Zsign`, `ServerInstaller`, `DownloadManager` and `ODSignPipeline` are static/singleton and cannot be substituted, so most defect classes in the bug audit cannot be regression-tested today.

The strategy below is ordered to match the roadmap: make the pipeline testable first, then grow coverage by risk, then add a device matrix that is actually executed.

---

## 1. What exists today

| File | Cases | What it pins down |
|---|---|---|
| `ODOCSPCoreTests.swift` | 2 | DER parsing binds status to the requested issuer+serial; wrong serial rejected |
| `ODOCSPFreshnessTests.swift` | 2 | freshness requires verified, determinate status and valid response times; revoked-but-expired is not fresh |
| `ODOCSPResponderAuthorizationTests.swift` | 3 | OCSP-signing EKU required; key-usage must permit digitalSignature; missing key usage does not override EKU |
| `ODZsignOutcomeTests.swift` | 5 | return value, callback, both, error and missing-callback outcomes |
| `StorageConcurrencyTests.swift` | 3 | concurrent background writes; failed store load preserves the path; new signing defaults do not delete imports |
| `ODAppleIDMaterialCleanupTests.swift` | 1 | cleanup removes only old app-owned directories |

**Quality note:** these tests are not decorative — `ODZsignOutcomeTests` covers exactly the class of bug that would otherwise ship a "successful" signing of an unsigned binary, and `StorageConcurrencyTests` covers the delete/restore path.

### 1.1 What CI does with them

`.github/workflows/build.yml`, `macos-26`, Xcode 26.4:

```
xcodebuild test -project Feather.xcodeproj -scheme Feather \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
make iphoneos
scripts/verify_ipa.sh packages/Odysseus.ipa
```

Verified green at `2a54e3b` and `fe0f37e`. **No coverage threshold, no lint step, no licence check, no device job.**

---

## 2. Coverage by risk, not by line count

| Risk area | Rows in matrix | Tests today | Target |
|---|---|---|---|
| Revocation (OCSP/X.509/DER) | 6 | 7 cases | keep; add network-level integration test |
| Storage / data consistency | 4 | 3 cases | extend to migration + quarantine |
| Signing pipeline | 20 | 5 cases (Zsign outcome only) | ≥ 20 cases via `SigningService` seam |
| Certificate lifecycle | 18 | 0 | ≥ 12 cases |
| Downloads | 3 | 0 | ≥ 6 cases |
| Sources / catalog | 16 | 0 | ≥ 10 cases |
| Install transports | 12 | 0 | unit tests on manifest generation + manual device matrix |
| Security invariants | 16 | 0 | lint-style tests (§5.2) |

A line-coverage number is a poor target here: the risk is concentrated in a few decision points (error mapping, URL encoding, state transitions), which unit tests can hit precisely.

---

## 3. The seam contract (prerequisite for everything below)

Implement M1 from `ODYSSEUS_ARCHITECTURE_AUDIT.md` §7.1 — four protocols, real implementations unchanged:

```swift
protocol SigningService: Sendable { func sign(_ request: SigningRequest) async throws -> SignedArtifact }
protocol InstallService: Sendable { func install(_ artifact: SignedArtifact, via: InstallTransport) async throws }
protocol SourceService: Sendable { func refresh() async -> [SourceSnapshot]; func add(_ url: URL) async throws -> SourceSnapshot }
protocol DownloadService: Sendable { func download(_ request: DownloadRequest, progress: @Sendable (Double) -> Void) async throws -> URL }
```

Tests then use fakes that **record calls and can throw on demand**:

| Fake | Injected failure | Unlocks |
|---|---|---|
| `FakeDownloadService` | transport error, move error, slow completion (configurable delay) | BUG-002, BUG-004, BUG-012 |
| `FakeSigningService` | zsign failure, missing cert, inspect failure | pipeline error mapping |
| `FakeInstallService` | server start failure, device rejection | transport selection |
| `FakeSourceService` | malformed JSON, timeout, 429 | source health, cache |
| `InMemoryCertificateStore` | keychain status codes | BUG-006, BUG-007 |

---

## 4. Fixtures (checked in, small, licensed for redistribution)

| Fixture | Size | Purpose |
|---|---|---|
| `fixtures/valid-app.ipa` | ~200 KB | a 1-screen SwiftUI app, signed ad-hoc, for import/inspect tests |
| `fixtures/frameworks-app.ipa` | ~400 KB | embedded `.framework` + `.appex`, for signing-order tests |
| `fixtures/watch-app.ipa` | ~300 KB | `Watch/` present, for removal behaviour |
| `fixtures/corrupt.zip`, `fixtures/not-an-ipa.ipa` | < 4 KB | error mapping |
| `fixtures/zipbomb.ipa` | **generated at test time**, not checked in | extraction limits |
| `fixtures/traversal.zip` | < 2 KB | entries named `../../evil` |
| `fixtures/ocsp/{good,revoked,unknown}.der` | < 4 KB | already-covered parsers, plus full-response tests |
| `fixtures/sources/{valid,missing-fields,deobfuscated,esign}.json` | < 20 KB | catalog decoding |
| `fixtures/certs/{valid,expired,mismatched-key}.p12` | < 10 KB | certificate validation (self-signed, **not** Apple-issued) |

Every fixture must be generated by a script in `scripts/fixtures/` so it can be regenerated and audited; no fixture may contain a real certificate or a real IPA.

---

## 5. Test layers

### 5.1 Unit (fast, hermetic, the bulk)

Targets, in roadmap order:

1. **Certificate export URL** (BUG-001) — round-trip a table of hostile passwords.
2. **State machine** (`ODSignPipeline` phases) — every transition, including import-after-grace (BUG-004) and import failure (BUG-002/003).
3. **Error mapping** — every `ODSignError`, `SigningFileHandlerError`, `CertificateFileHandlerError` to a user-facing string; a test that fails when a new case has no mapping.
4. **Archive limits** (S-05) — entry count, expanded size, traversal rejection.
5. **Certificate lifecycle** — delete failure (BUG-006), keychain status (BUG-007), expiry boundary at exactly `now`, mismatched key/cert.
6. **Source service** — cache write/read, health states, duplicate detection, coalesced refresh (BUG-011).
7. **Manifest generation** — `ServerInstaller+Compute` output for a known app; assert the plist round-trips through `PropertyListSerialization`.
8. **Preferences migration** — new `ODPrefs` keys default correctly on an existing install.

### 5.2 Invariant tests (cheap, catch regressions that reviews miss)

| Test | Assertion |
|---|---|
| `PlistInvariantTests` | every transport the code can select has its required Info.plist keys (`NSLocalNetworkUsageDescription`, `UIBackgroundModes`, ATS exceptions) |
| `DependencyPinTests` | no `branch:` requirement in any `Package.swift`; `Package.resolved` exists and is committed |
| `LicenseManifestTests` | every file referenced by `license_plist.yml` exists (catches the `LICENSE_EllEKIT` case bug, L-03) |
| `NoForceUnwrapTests` | CI grep fails on `try!`/`as!` outside the allow-list (3 known sites, shrinking to 0) |
| `NoPrintTests` | CI grep fails on `print(` outside tests |
| `KeychainAccessibilityTests` | every `SecItemAdd` in the codebase passes `kSecAttrAccessible*` |

### 5.3 Integration (in-app, not device)

- Sign a `valid-app.ipa` fixture with a self-signed certificate through the real `SigningHandler`/`ZsignHandler` path, then assert: bundle id changed, entitlements embedded, nested frameworks re-signed, signature present.
- Import → storage → library query → delete → restore round trip against a temporary SQLite store.
- OCSP checker against a local `URLProtocol` stub serving the DER fixtures (good / revoked / unknown / timeout).

These need no device and no Apple ID, and they cover the two most dangerous silent failures (unsigned output accepted, delete losing data).

### 5.4 Device matrix (manual, scripted, executed before every release)

Because zero device verification exists, this matrix is a **release gate**, not a nice-to-have. Each row records device model, iOS build, transport, outcome, and the log excerpt.

| # | Scenario | Expected |
|---|---|---|
| D-01 | Import IPA from Files, sign with imported p12, install via semi-local server | app launches on device |
| D-02 | Same via fully-local TLS transport | app launches |
| D-03 | Same via pairing/IDevice transport | app launches |
| D-04 | Sign an app with an embedded framework and extension | launches, extension works |
| D-05 | Sign with a revoked certificate under **Block** policy | refused before signing |
| D-06 | Sign with OCSP unreachable under **Block** policy | decision matches documented policy (T-01) |
| D-07 | Apple ID sign-in incl. 2FA, then sign + install | app launches; certificate listed in the Apple developer account |
| D-08 | Download a 300 MB app over Wi-Fi, background the app for 5 min | download completes (BUG-005) |
| D-09 | Lost local-network permission, then install | clear error, not a hang |
| D-10 | Lockscreen / app switch during signing | no crash; state consistent on return |
| D-11 | Delete a certificate with a deliberately unreadable file | user is told; no orphan (BUG-006) |
| D-12 | Export a `.p12` with password `p@ss&w0rd`, re-import it | password survives (BUG-001) |
| D-13 | Cold start with 200 library entries | < 2 s to interactive |
| D-14 | Upgrade install: previous build's Core Data store opens | no data loss |
| D-15 | VoiceOver pass over Library + Signing | all controls labelled (F13) |

Recording format: `Documentation/Audit/device-runs/<date>-<ios>-<device>.md`, one file per session, committed. A release without a committed D-01…D-14 pass for the current build is not releasable.

---

## 6. Sequencing against the roadmap

| Phase | Testing work | Gate |
|---|---|---|
| 0 | Invariant tests (5.2), BUG-001/002 URL + state tests | CI red on any force-unwrap/print/licence-path regression |
| 1 | Seams + fakes; error-mapping tests; archive-limit tests | pipeline reachable by tests without a device |
| 2 | Integration suite (5.3); fixture scripts | signing verified against fixtures in CI |
| 3 | Source service tests; cache/health | offline storefront provable |
| 4 | Device matrix executed and committed for two device generations | first genuinely "verified" release |
| 5 | Coverage reporting (informational), F-14 accessibility checks | sustained |

---

## 7. CI changes (concrete)

```yaml
# add after checkout
- name: Assert pinned dependencies
  run: test -f Package.resolved && ! grep -rq "branch:" --include=Package.swift .

- name: Local package tests
  run: |
    swift test --package-path AltSourceKit
    swift test --package-path NimbleKit

- name: Lint invariants
  run: scripts/ci/invariants.sh   # force-unwraps, print(, plist keys, licence paths

- name: Unit + integration tests with coverage
  run: xcodebuild test ... -enableCodeCoverage YES
```

`scripts/ci/invariants.sh` does not exist yet; creating it is roadmap task ODY-004.

---

## 8. Commands for a capable machine (none of these were run here)

```
git submodule update --init --recursive

xcodebuild test -project Feather.xcodeproj -scheme Feather \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -derivedDataPath build/tests CODE_SIGNING_ALLOWED=NO

swift test --package-path AltSourceKit
swift test --package-path NimbleKit

make iphoneos
scripts/verify_ipa.sh packages/Odysseus.ipa
```

Expected: all 16 existing cases pass; the IPA verifier exits 0. If `xcodebuild` reports missing `Zsign`/`IDeviceKitten` modules, the submodules were not initialised — that is an environment failure, not a test failure.

**Verification ledger for this document:** no test was executed in this audit. Every statement about the current suite comes from reading the test sources and from CI run `41198043032`/`41219757550`, both green.
