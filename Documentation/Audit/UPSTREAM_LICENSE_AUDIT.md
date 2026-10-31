# Upstream licence audit

**Audit date:** 2026-10-31 · **Scope:** every licence-bearing artefact linked into, vendored in, or considered for Odysseus.
**Not legal advice.** Items marked **for review** require a lawyer or the rights-holder before distribution.

## 0. Method

1. Licence files were read **from disk** where the component is in this tree (`LICENSE`, `SideSign/LICENSE`, `AltSourceKit/LICENSE`, `NimbleKit/LICENSE`, `LICENSE_ELLEKIT`).
2. Remote dependency licences were read from the GitHub API *and*, where the API reported `NOASSERTION`/`Other`, the actual `LICENSE` body was fetched and read.
3. Compatibility reasoning uses the FSF's stated view that GPLv3 is one-way compatible with Apache-2.0 and that GPLv3 §13 permits combining with AGPLv3.
4. No component was built, so transitive *runtime* licence obligations (e.g. a dependency pulled in by a dependency) are only visible where `Package.swift`/`Package.resolved` lists them.

---

## 1. Licence inventory

### 1.1 In this repository

| Component | Location | Licence | Verified | Obligation |
|---|---|---|---|---|
| Odysseus application code | `Feather/**`, `OdysseusTests/**` | **GPL-3.0** (root `LICENSE`) | file read | full corresponding source on distribution; notices intact; no added restrictions |
| AltSourceKit | `AltSourceKit/` | **MIT** © 2025 CLARATION | file read | retain notice |
| NimbleKit | `NimbleKit/` | **MIT** © 2025 CLARATION | file read | retain notice |
| SideSign | `SideSign/` | **AGPL-3.0** | file read | AGPL obligations on the combined binary |
| ElleKit | `LICENSE_ELLEKIT` + `Resources/ellekit.deb` | **BSD-3-Clause** © 2022 Évelyne Bélanger | file read | retain copyright + disclaimer; no endorsement claim |
| LiveContainer Mach-O fixup | `Feather/Utilities/MachO/MachOUtils.m` | **Apache-2.0** (declared in the file header, cites upstream commit `3a029b6b…`) | file read | keep attribution; keep any upstream `NOTICE`; combined work stays GPL-3.0 |
| Apple WWDR certificates ×6 | `Feather/Resources/AppleWWDRCA{,G2,G3,G4,G5,G6}.cer` | Apple trust-store material | filenames only | **for review** — redistribution of Apple root/intermediate certificates is common in this ecosystem but is not covered by any licence grant in this repository |
| Zsign | `Zsign/` submodule (not checked out) | **MIT** (declared in `license_plist.yml`) | declaration only | retain notice; **verify** once the submodule is initialised |
| idevice / IDeviceKitten | `IDeviceKitten/` submodule | **MIT** (declared) | declaration only | retain notice; verify |

### 1.2 Swift Package Manager dependencies

| Package | Pinned how | Licence | Verified |
|---|---|---|---|
| `vapor/vapor` | branch/range in `project.pbxproj`, **no `Package.resolved`** | MIT | GitHub API |
| `kean/Nuke` | same | MIT | GitHub API |
| `marmelroy/Zip` | same | MIT | GitHub API (last push 2024-08-05) |
| `tsolomko/SWCompression` | same | MIT | GitHub API |
| `mono0926/LicensePlist` | same | MIT | GitHub API |
| `BitByteData` | same | MIT | GitHub API |
| `apple/swift-crypto` 4.3.1 | **exact** in `SideSign/Package.swift` | Apache-2.0 | GitHub API |
| `SideStore/libdeflate` | **branch `master`** | MIT | GitHub API |
| `mahee96/CodeSignKit` | **branch `main`** | **AGPL-3.0** (API reports `Other`; licence body is the AGPL v3 text) | API + file body |
| `mahee96/GSACryptoKit` | **branch `main`** | **AGPL-3.0** (same situation) | API + file body |
| `mahee96/AnisetteKit` | **branch `main`** | **AGPL-3.0** (same situation) | API + file body |

**Finding L-01 (High, legal):** the AGPL footprint is **not** confined to the `SideSign/` folder. Three of SideSign's five dependencies are AGPL-3.0 and are statically linked into the product. The combined binary therefore contains four AGPL-3.0 components plus the GPL-3.0 application.

**Finding L-02 (High, supply chain):** those same three packages are pinned to a **moving branch** with no `Package.resolved`, so the exact code — and therefore the exact licence text — can change between builds without any change in this repository. `SideSign/Package.swift:33–38` is the evidence.

---

## 2. Compatibility analysis

| Combining | Permitted? | Result |
|---|---|---|
| MIT / BSD-3 / Apache-2.0 into GPL-3.0 | Yes | Combined work GPL-3.0; notices retained |
| GPL-3.0 code into this app | Yes, same licence | No change |
| **AGPL-3.0 code into this GPL-3.0 app** | Yes — GPLv3 §13 explicitly permits linking/combining with AGPLv3 | The GPL-3.0 terms continue to cover the GPL part, **and AGPL §13 (network interaction) applies to the combination as such** |

### 2.1 What AGPL §13 means for this specific product

§13 requires that users interacting with the program **remotely over a network** be offered the Corresponding Source.

Odysseus ships a **local HTTP server** (`ServerInstaller`, `0.0.0.0:<4000–8000>`) that the device itself, or the local network, can reach during an install. Whether "the device fetching its own manifest over loopback/LAN" is "interaction through a network" in the §13 sense is **not settled by the licence text** and is **for review**. Two readings exist:

- *Narrow:* the server serves the user's own device during an install; §13 is not triggered; normal GPL-3.0 source-provision on distribution suffices.
- *Broad:* any network-reachable interface (install server, WebDAV if added later) is interaction; source must be offerable from that interface.

**Practical consequence in both readings:** the project must publish complete corresponding source for the distributed binary, including `SideSign` and the three AGPL packages, and must not add restrictions on top. Odysseus already publishes its source, so the gap is *completeness of notices and pinned provenance*, not secrecy.

### 2.2 What would relicense the product

| If this is copied/linked | Effect |
|---|---|
| LiveContainer runtime (AGPL) | Whole product effectively AGPL-3.0; container code is entangled with SpringBoard hooks and entitlements that cannot be shipped anyway |
| SideStore app code (AGPL) | Same; and it duplicates functionality already present via `SideSign` |
| FlekDeck (AGPL) | Same, plus it is a 2026-10-29 fork with 56 stars |
| FlekPair (**no licence**) | **Prohibited** — no rights granted at all |
| FlareStore / Zeus (closed) | **Prohibited** — no source, no licence |
| LiveContainer-FS (Apache-2.0) | Permitted, but its runtime hook code is useless here (§2.6 of the register) |

---

## 3. Obligations checklist before any binary is distributed

| # | Obligation | Current state |
|---|---|---|
| 1 | Ship the full GPL-3.0 text | **done** (`LICENSE`) |
| 2 | Ship licence texts for all bundled components | **partial** — `license_plist.yml` generates acknowledgements at build time; see defects L-03/L-04 |
| 3 | State modifications to GPL-3.0 files | **partial** — file headers are retained but there is no consolidated "changes" statement |
| 4 | Retain copyright notices inside source files | **done** — spot checks of `FR.swift`, `SigningHandler.swift`, `MachOUtils.m` retain upstream headers |
| 5 | Publish complete corresponding source for the *distributed* build (incl. AGPL parts) | **done in principle** — public repository; but the exact dependency revisions are not recorded (L-02) |
| 6 | Offer source from a network interface if §13 applies | **not implemented** — for review |
| 7 | Do not impose extra restrictions (e.g. proprietary EULA, anti-fork clause) | **compliant** — none found in `README.md`, `SECURITY.md`, `LICENSE` |
| 8 | Apache-2.0 `NOTICE` retention for the Mach-O fixup | **defective** — attribution exists as a code comment only; no `THIRD_PARTY_NOTICES.md` |

---

## 4. Defects

| ID | Severity | Defect | Evidence | Fix |
|---|---|---|---|---|
| **L-01** | High | AGPL code is linked from four packages, not one; not disclosed to users | `SideSign/Package.swift:33–38`; three deps' `LICENSE` = AGPL | add `THIRD_PARTY_NOTICES.md` listing every AGPL component and their revisions; state the combined-work position in `README`/`LICENSE` |
| **L-02** | High | Three AGPL deps and `libdeflate` are pinned to branches; no root `Package.resolved` | same file | pin to revisions; commit `Package.resolved`; enable Dependabot for Swift |
| **L-03** | Medium | `license_plist.yml` points at `LICENSE_EllEKIT` (case mismatch) and `Zsign/LICENSE_LC` (unverified path) | file content vs `ls` | correct paths; make the licence job fail when a referenced file is missing |
| **L-04** | Medium | No consolidated third-party notices file; Apache-2.0 attribution exists only as a code comment | repo root | add `THIRD_PARTY_NOTICES.md`, generated in CI, checked in |
| **L-05** | Medium | Bundled Apple WWDR certificates have no stated redistribution basis | `Feather/Resources/AppleWWDRCA*.cer` | **for review**; if unclear, download at runtime from `certs.apple.com` (ATS exception already exists) instead of bundling |
| **L-06** | Low | `Settings.bundle/Root.plist` ships Apple's template text with no attribution requirement issue — recorded so it is not mistaken for a defect | — | none |
| **L-07** | Info | FeatherPlus excluded, but its GPL-3.0 status is recorded so a future reader does not assume it is unavailable for licensing reasons | register §2.10 | none |

---

## 5. Reuse decisions with licence consequences

| Candidate code | Licence | Decision | Consequence |
|---|---|---|---|
| feather `UpdateManager`, `Storage+SourceMetadata` | GPL-3.0 | **reuse with attribution** | none beyond existing GPL |
| RyukSign `AppUpdateChecker`, `MachOEntitlements`, `InfoPlistPlan`, `PlistDiff`, `BatchJobRunner`, `SigningLog` | GPL-3.0 | **adapt with attribution** | none beyond existing GPL |
| Ksign settings taxonomy | GPL-3.0 | **adapt** (layout/idea) | none |
| SideStore `SideBackup` format | AGPL-3.0 | **do not copy**; design only | copying adds AGPL surface |
| LiveContainer / FlekDeck runtime | AGPL-3.0 | **do not copy** | would relicense the product and cannot ship |
| LiveContainer-FS | Apache-2.0 | **permitted** if ever needed | requires NOTICE |
| FlekPair | none | **prohibited** | — |
| FlareStore / Zeus | none (closed) | **prohibited** | — |

---

## 6. Verdict

The product can remain **GPL-3.0** and can absorb every GPL-3.0 donor in the register. It **cannot** absorb the AGPL-3.0 container/store projects without effectively becoming an AGPL-3.0 product — which is acceptable only if the project intends that, and is unacceptable if the intent is to keep the current licence posture unchanged.

The two things that must be fixed regardless of feature work are **L-01** (disclose and enumerate the AGPL components) and **L-02** (pin them). Both are cheap; both are prerequisites for calling any build "distributable".
