# eMediBlock

Smart contracts, benchmarks, attack suite and offline experiment code for:

> **A Secure Service-Oriented Framework for Electronic Health Record Management Using Blockchain**
> Kaveri Banerjee, Soumyadip Chowdhury, Sajal Saha, Hirak Mazumdar, Sunil Kumar Singh

This repository is the reproducibility artifact for the paper. Everything a
reader needs in order to check a claim made in the manuscript is here, and the
map from claim to file to command is in [`docs/MANUSCRIPT_MAP.md`](docs/MANUSCRIPT_MAP.md).

> **Dataset, not code.** The healthcare dataset used in Section 4.1 lives in a
> separate repository — Reference [27] of the paper,
> [imranbdcse/healthcaredatasets](https://github.com/imranbdcse/healthcaredatasets/blob/DataScience/healthcare_dataset.csv).
> It contains no code. `data/download_dataset.py` fetches it and reproduces the
> 20-record selection.

---

## Status — read this before citing any number

| | |
|---|---|
| Contracts | Written for Solidity 0.8.20, as stated in Section 3 of the paper. |
| Benchmarks | Written. **Must be run locally to produce `results/results.json`.** |
| Attack suite | Written. Run with `npm test`. |

**The numbers currently printed in Sections 4.1 and 4.3 of the manuscript were
produced by an earlier implementation.** After running `npm run bench`, compare
what `results/results.json` says against what the paper says. Where the two
disagree, the measured value is correct and the paper must be corrected. Every
benchmark file repeats this warning at the top, because it is the one way this
repository could quietly mislead someone.

---

## Quick start

```bash
git clone https://github.com/hirakmaa/eMediBlock.git
cd eMediBlock

npm install                 # Hardhat toolchain
npm run compile             # solc 0.8.20

npm test                    # the attack suite — Section 4.2
npm run bench               # gas and size measurements — Sections 4.1, 4.3

python3 -m pip install -r offline/requirements.txt
python3 data/download_dataset.py
npm run offline             # enumeration, recovery, FHIR, scheduler
npm run figures             # regenerate every figure from the raw output
```

`npm run all` does the lot in order. To measure against a public test network
instead of the local chain, copy `.env.example` to `.env`, fill in an Infura
endpoint and a funded Sepolia test key, then `npm run bench:sepolia`.

---

## What implements what

The paper's contributions C1–C6 map onto files as follows.

| | Contribution | Implemented in | Verified by |
|---|---|---|---|
| **C1** | Consent withdrawal takes effect at once | `contracts/EMediBlockConsent.sol` | `test/attacks` A3–A5, `offline/src/consent_enumerate.py` |
| **C2** | Accountable emergency access | `contracts/EMediBlockEmergency.sol` | `test/attacks` A9–A11, `offline/src/emergency_enumerate.py` |
| **C3** | Batched Merkle anchoring | `contracts/EMediBlockAnchor.sol` | `bench/gas_anchor_batch.js` |
| **C4** | Consent-gated erasure-coded recovery | `contracts/EMediBlockRecovery.sol` | `offline/src/erasure_recovery.py` |
| **C5** | Integrity over canonical HL7 FHIR | `offline/src/fhir_convert.py` | `offline/src/fhir_validate.py` |
| **C6** | Congestion-aware scheduling | `offline/src/scheduler_sim.py` | same |

The **coarse-grained** contribution — the service decomposition and the single
consent policy every service is invoked through — is visible in the dependency
direction: services call *downward* into `EMediBlockConsent.canRead` and nothing
calls back. No service carries its own permission test. That is why the security
objectives of Section 3.1 are properties of the framework rather than of
individual services.

### Contract suite

```
contracts/
├── EMediBlockRegistry.sol      identities and roles            (F1)
├── EMediBlockConsent.sol       epoch-fenced consent            (C1, F3, F4)
├── EMediBlockAnchor.sol        batched Merkle anchoring        (C3, F2, F9)
├── EMediBlockEmergency.sol     accountable break-glass         (C2, F5)
├── EMediBlockRecovery.sol      consent-gated recovery          (C4, F8)
├── MedicalHealthRecord.sol     record service, mediated reads  (F2, F4, F9)
├── baseline/
│   └── ConventionalConsent.sol the list-scan design, for comparison only
├── test/                       test-only helpers, never deployed
└── legacy/
    └── MedicalHealthRecord_v0.4.17.sol   the original prototype, preserved
```

The split is by **responsibility**, not by service, so that the consent policy
has exactly one implementation. `EMediBlockEmergency` is deliberately separate:
its logging and expiry obligations are far stricter, and keeping it apart means
a caller cannot reach the consent contract directly and bypass them.

### On `contracts/legacy/`

`MedicalHealthRecord_v0.4.17.sol` is the authors' original prototype, kept
verbatim and **not** deployed. It is in the repository so that the design's
evolution is on the record. It implements none of C1–C6: it has no access
control of any kind, no consent mechanism, no emergency route, no batched
anchoring and no recovery, and it targets a Solidity version that has not
compiled since 0.5. Its working descendant is `contracts/MedicalHealthRecord.sol`,
which keeps the original record model and event names and adds everything the
original lacked.

---

## The one result worth understanding

Consent withdrawal is correct **under adversarial transaction ordering**. That
is the claim the paper stands on, and it is the one this repository makes
checkable.

Every patient carries a monotonically increasing consent *epoch*. A grant is
stamped with the epoch current when it was made, and is valid only while the
stamp still matches. Two things follow:

- `revokeAll()` advances the epoch by one. That single storage write invalidates
  every outstanding grant at once, so there is no intermediate state in which one
  doctor is revoked and another is not — nothing for an attacker who controls
  block ordering to interleave a read into.
- `grantConsent(grantee, recordType, expectedEpoch)` reverts on a stale epoch. A
  grant transaction still sitting in the mempool when the epoch advances cannot
  land afterwards against the patient's revised intention.

Attack **A4** in the suite is exactly this: sign a grant, revoke before it is
mined, then try to land the grant. It must revert.

The conventional design, rebuilt in `baseline/ConventionalConsent.sol`, fails
both ways: withdrawal is per-grantee, so the read window exists, and the
permission check scans a list, so its cost grows with the number of grants.

---

## Repository layout

```
contracts/     Solidity sources (above)
test/          attack suite (Section 4.2) and unit tests
bench/         gas and size measurement; writes results/
offline/       enumeration, recovery, FHIR and scheduler experiments
data/          dataset fetch and the 20-record selection
results/       measured output — the evidence for the paper's numbers
figures/       figure generation from raw output
docs/          MANUSCRIPT_MAP.md and REPRODUCE.md
```

---

## Requirements

- Node.js ≥ 18 and npm
- Python ≥ 3.10 (`offline/requirements.txt`)
- No account, key or paid service is needed for the local benchmarks. Sepolia
  runs need an RPC endpoint and a funded test key; the test currency has no
  value.

---

## Citing

See [`CITATION.cff`](CITATION.cff). Please cite both the paper and the archived
software release.

## Licence

MIT — see [`LICENSE`](LICENSE).
