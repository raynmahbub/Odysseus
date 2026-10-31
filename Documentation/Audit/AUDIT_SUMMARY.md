# Odysseus — audit summary

**Audit date:** 2026-10-31
**Repository:** `raynmahbub/Odysseus` · **Branch audited:** `arena/36737ef3-odysseus` · **HEAD:** `6ee21d6` (= `master`, clean tree)
**Mode:** audit and documentation only. No production code was changed, and nothing was committed or pushed.

---

## 1. The seven questions, answered directly

### 1.1 How much of the product exists?

**Most of the hard part exists; the edges are missing.**

118 capabilities were assessed across eight groups:

| Status | Count | Share |
|---|---|---|
| COMPLETE (end-to-end, reachable, build-verified) | 51 | 43% |
| PARTIAL (implemented but degraded) | 37 | 31% |
| BROKEN (reachable with a confirmed defect) | 1 | 1% |
| MISSING | 17 | 14% |
| UNSUPPORTED (not achievable here) | 7 | 6% |
| NEEDS_INVESTIGATION | 5 | 4% |

That is a real product: acquisition, source parsing (AltStore and ESign formats, incl. deobfuscation), IPA import and inspection, Zsign-based signing with tweak injection, three install transports, certificate lifecycle with **genuine OCSP revocation checking**, Apple ID signing via a vendored `SideSign`, a storefront with cross-source duplicate grouping, and a library with quarantine-safe deletes.

It is also **unverified**: four rows out of 118 have unit-test evidence, and **zero** have device evidence. The build is green (`xcodebuild test` + `make iphoneos` + `verify_ipa.sh`), which proves it compiles and packages — nothing more.

### 1.2 What is genuinely missing?

Ordered by how much it hurts:

1. **Credential safety** — the `.p12` password is a plain Core Data attribute, the p12 directory has no protection class, and `UIFileSharingEnabled` exposes it to Files (S-03).
2. **Meaningful verification of its own output** — `Zsign.checkSigned` is a presence check, not signature verification; nothing checks nested Mach-O signatures or bundle-id/profile consistency (C11, C18, ODY-201).
3. **Offline source cache** — `SourcesViewModel.sources` is memory-only, so the storefront is empty until the network answers (A07).
4. **Update detection** — no way to know an installed app has a newer version (A14/E07).
5. **Entitlements and Info.plist inspection** — the pipeline can *replace* an entitlements file but cannot *show* entitlements and cannot edit a plist beyond a fixed set of toggles (C06, C07, F05, F06).
6. **Failure legibility** — a failed import leaves a permanently "downloading" row; a slow import can be cancelled by a 3-second timer (ODY-BUG-002/004).
7. **Operational maturity** — no accessibility, no second language, no crash reporting, no bulk operations, no backup (F10/F12/F13, E09, E14).

### 1.3 What is the best upstream value?

| Rank | Source | What to take | Why |
|---|---|---|---|
| 1 | **RyukSign** (GPL-3.0, `844466c`) | `AppUpdateChecker`, `MachOEntitlements`, `InfoPlistPlan`/`PlistDiff`, `BatchJobRunner`, `SigningLog` | Covers four of the six real gaps; same lineage, so the code drops into the existing types |
| 2 | **feather** (GPL-3.0, `7078b05`) | `UpdateManager`, `Storage+SourceMetadata` | The direct ancestor; the delta is small and known |
| 3 | **Ksign** (GPL-3.0, `c14dedc`) | Settings/installation taxonomy | The most recently maintained sibling; useful for UX structure, not logic |
| 4 | **SideStore** (AGPL) | *Design* only: pairing, anisette model, backup format | AGPL blocks code reuse |

Everything else is either excluded (FeatherPlus), unusable (LiveContainer/FlekDeck runtime), unlicensed (FlekPair), or unresolvable (FlareStore/Zeus).

### 1.4 Direct reuse vs adapt vs impossible

| Verdict | Components |
|---|---|
| **Direct reuse** (already in the tree, keep notices) | AltSourceKit, NimbleKit, SideSign, Zsign, IDeviceKitten, ElleKit, the Apache-2.0 Mach-O fixup |
| **Adapt** | RyukSign update checker, entitlements reader, plist diff, batch queue, signing log; feather update manager |
| **Impossible / prohibited** | LiveContainer runtime (128 keychain groups, in-process guest code, no isolation), SideStore/FlekDeck code (AGPL rewrites the product's licence), FlekPair (no licence), FlareStore/Zeus (no source) |

### 1.5 What should be built first?

Phase 0 — six small tasks, roughly one week, all defect fixes, no features:

1. Percent-encode the export and gate it behind biometrics (ODY-001).
2. Make download/import failure terminal and specific; kill the 3-second race (ODY-002).
3. Remove the three crash sites (ODY-003).
4. Add the CI invariant gate (ODY-004).
5. Declare the local network and bind loopback (ODY-005).
6. Pin dependencies and publish third-party notices (ODY-006).

Then **one** structural task, ODY-101 (four service protocols), because every later test and feature depends on it.

### 1.6 What is the target architecture?

A **single app target with folder-level boundaries** and injected protocols — not frameworks, not modules:

```
App/ (lifecycle, router) → Features/ (views + view models) → Domain/ (protocols, pure models)
                                   ↑ injection
                         Infrastructure/ (Zsign, SideSign, Vapor, Core Data, Keychain, Files)
```

Rules: `Features` imports only `Domain`; `Domain` imports nothing from `Infrastructure`; no `static let shared` outside `App/`; no view calls `FR`, `Zsign`, or `ServerInstaller` directly. Migration is five shippable steps (M1–M5 in the architecture audit); no big-bang rewrite.

### 1.7 Fastest path to a stable release?

**Phase 0 → Phase 1 (seams + certificate store) → ODY-201 (real signature verification) → ODY-203 (transport diagnostics) → ODY-301 (offline sources) → ODY-501 (executed device matrix).** Skip Phase 4 entirely. That sequence produces a build that signs verifiably, explains its failures, works offline, and has been proven on hardware. Editors and batch signing are multiplicative on a pipeline that is not yet proven — building them first is the classic way to end up with a wide product that cannot be trusted.

---

## 2. Top findings

### 2.1 Must fix before any distribution

| ID | Finding | Doc |
|---|---|---|
| S-01 / ODY-BUG-001 | Export sends the `.p12` **and a raw, unencoded password** to a caller-supplied URL, behind an alert that does not show the destination and without biometrics | security §3, bugs §1 |
| S-02 | `odysseus://import-certificate` imports a signing identity **silently**, and it can become the default identity | security §3 |
| S-03 | Certificate password in plain Core Data; p12 directory unprotected; `Documents/` exposed via file sharing and included in backups | security §3 |
| S-04 / ODY-BUG-014 | Install server binds `0.0.0.0` with no auth; `NSLocalNetworkUsageDescription` missing | security §3 |
| ODY-BUG-005 | `BGTaskScheduler.register` is called for a per-download identifier after launch — unsupported, crash-or-silently-ignored | bugs §1 |
| ODY-BUG-002/004 | A failed import dead-ends the download row forever; a slow import is cancelled by a 3-second timer | bugs §1 |
| L-01 / L-02 | Four AGPL-3.0 packages are linked (not just `SideSign`), three of them pinned to **branches** with no `Package.resolved` | licences §1–§4 |

### 2.2 What is strong (and should be protected in review)

- **OCSP revocation** is genuinely implemented and genuinely tested: DER parsing, signature verification, responder authorisation, Apple trust anchoring, freshness, three policies.
- **Persistence discipline**: immutable snapshots across queues, background contexts, delete-with-quarantine-and-restore, covered by tests.
- **Local TLS identity** is per-device, `0o700`/`0o600`, `completeFileProtection`, with no bundled shared key and no silent plaintext fallback.
- **One pipeline** for all three entry points, which is why the defect list is short and concentrated rather than scattered.

---

## 3. Deliverables

All ten documents are in `Documentation/Audit/`:

| # | Document | Contents |
|---|---|---|
| 1 | `BASELINE_AUDIT.md` | repo state, build facts, module map, CI evidence, verification ledger, reconciliation with `docs/` |
| 2 | `ODYSSEUS_FEATURE_MATRIX.md` | 118 rows, seven statuses, file paths, upstream reference, strategy, P0–P4, evidence |
| 3 | `UPSTREAM_SOURCE_REGISTER.md` | 11 sources resolved and pinned, per-project value, unfindable projects recorded |
| 4 | `UPSTREAM_LICENSE_AUDIT.md` | full licence inventory incl. transitive SPM licences, AGPL analysis, obligations, defects L-01…L-07 |
| 5 | `ODYSSEUS_ARCHITECTURE_AUDIT.md` | actual vs intended structure, flows, concurrency, strengths/weaknesses, target architecture, 5-step migration |
| 6 | `ODYSSEUS_BUG_AND_RELIABILITY_AUDIT.md` | 17 confirmed defects + 8 theoretical, with fix and regression test each |
| 7 | `ODYSSEUS_TESTING_STRATEGY.md` | what exists, risk-based targets, seams, fixtures, CI changes, 15-row device matrix |
| 8 | `ODYSSEUS_IMPLEMENTATION_ROADMAP.md` | Phase 0–5, 24 tasks with files, acceptance criteria, tests, complexity, dependency graph |
| 9 | `ODYSSEUS_SECURITY_REVIEW.md` | threat model, 13 findings, positive controls, accepted risks, release gate |
| 10 | `AUDIT_SUMMARY.md` | this document |

---

## 4. Verification ledger

| Claim type | Basis |
|---|---|
| Repository state, file contents, line numbers | read directly from the working tree at `6ee21d6` |
| Build succeeds, 16 tests pass | CI runs `41198043032` (master, success, 20m25s) and `41219757550` (success); not re-run here |
| Upstream identity, licence, activity | GitHub API + shallow clones at the SHA listed in the register; licence bodies read |
| AGPL in SideSign dependencies | `Package.swift` + each dependency's `LICENSE` body fetched and read |
| Any device behaviour | **not verified** — no device or simulator was available |
| Any performance claim | **not measured** |
| Any exploit | **not attempted**; security findings are static |

### 4.1 Limits of this audit

1. **No execution.** Linux host, no Xcode, no simulator, no device, empty submodules. Everything is static or CI-derived.
2. **Submodules unpopulated.** `Zsign` and `IDeviceKitten` internals were not inspected; statements about signing order and pairing are marked `NEEDS_INVESTIGATION`.
3. **Third-party extraction behaviour** (`marmelroy/Zip`, `SWCompression`) was not executed, so S-05 remains conditional.
4. **Two upstreams are unresolvable.** FlareStore and Zeus have no canonical public source; no claim about their internals is made anywhere.
5. **No dynamic analysis of deep links or the local server** was performed; those findings are code-path findings, not demonstrated attacks.

---

## 5. Scope decisions carried through this audit

- **FeatherPlus:** excluded, recorded as considered-and-dropped.
- **LiveContainer / FlekDeck / SideStore:** separate high-risk workstreams. Their code is **AGPL-3.0**, and the container runtime is architecturally incompatible (see architecture §8); design concepts only, no code reuse, no merge into the signing app.
- **FlareStore / Zeus:** closed-source concept references. No source, no licence, **no reuse claim** — and no mention in public-facing product documentation.
- **`docs/` package:** left untouched. `Documentation/Audit/` is authoritative where they disagree; three specific corrections to the earlier package are recorded in `BASELINE_AUDIT.md` §9.

---

## 6. Branch note

The task requested a branch named `arena/odysseus-comprehensive-audit`. This session is bound to `arena/36737ef3-odysseus`, which is the branch that was checked out and verified at `6ee21d6` (= `master`, clean). All work is on that branch; creating or switching to another branch would detach the work from the session, so it was not done.

**Nothing has been committed.** The ten documents are working-tree changes for review, per instruction.

---

## 7. Bottom line

> Odysseus is a real, working sideloading app with one genuinely excellent subsystem (revocation) and one genuinely dangerous one (credential handling).
>
> The product is roughly **40% complete by capability, ~5% by verification**. The missing 60% is not "more screens": it is signature verification, offline sources, update detection, entitlements visibility, and failure reporting.
>
> Spend one week removing the credential and crash risks, two to three weeks making the pipeline testable, then build features only on top of that. A stable release is reachable in **roughly 8–10 weeks** of focused work — and it will be stable in the sense that matters: signing is verified, failures are explained, and the device matrix has actually been run.
