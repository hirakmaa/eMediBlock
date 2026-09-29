# Manuscript map

Every quantitative claim in the paper, the file that produces it, and the
command that regenerates it. This is the document to hand a reviewer who asks
"where does that number come from?"

> **Read the Status column honestly.** Figures marked ⚠️ come from an earlier
> implementation and have not yet been reproduced by the code in this
> repository. Run the command, then either confirm the paper's number or change
> it. Do not leave a ⚠️ row unresolved at resubmission.

---

## Section 4.1 — Deployment, workload and baseline measurements

| Claim in the paper | Value stated | Produced by | Command | Status |
|---|---|---|---|---|
| Deployed contract size, before → after optimisation | 124,131 → 106,130 bytes (−14.5 %) | `bench/contract_size.js` | `npx hardhat run bench/contract_size.js` | ⚠️ re-measure |
| Deployment gas as share of block target | 68.88 % → 37.56 % | `bench/contract_size.js` | same | ⚠️ re-measure |
| Gas use across 20 transactions | 34.74 – 80.28 % of limit | `bench/` + `results/gas-report.txt` | `npm test` | ⚠️ re-measure |
| Gas saving by time of day, peak | 53.53 % at 3:00 p.m. | `offline/src/gasprice_model.py` | `npm run offline` | ⚠️ re-measure |
| Gas saving at 3:00 a.m. | 21.68 % | `offline/src/gasprice_model.py` | same | ⚠️ see note 1 |

**Note 1.** The published figure was 9.58 %, which contradicted the bar in the
chart and the complement of the 78.32 % usage figure. It was corrected to 21.68 %.
Confirm against the raw log before resubmission.

**Note 2 — EIP-170.** A single deployed contract cannot exceed 24,576 bytes, so
a six-figure "contract size" must be the sum across the suite, or the creation
bytecode. State in the paper which you mean; `contract_size.json` reports both
per contract.

---

## Section 4.2 — Security evaluation

| Claim in the paper | Value stated | Produced by | Command | Status |
|---|---|---|---|---|
| Consent rules, exhaustive enumeration | 2,985,984 sequences at depth 6, 0 violations | `offline/src/consent_enumerate.py` | `npm run offline` | ⚠️ re-run |
| Baseline counterexamples | 3 | same | same | ⚠️ re-run |
| Ordering attack leak, baseline | 25.0 / 33.3 / 37.5 % at 2 / 3 / 4 doctors | same | same | ⚠️ re-run |
| Ordering attack leak, eMediBlock | 0 % | same, and `test/attacks` A4–A5 | `npm test` | ✅ asserted in tests |
| Emergency enumeration | 279,936 sequences at depth 7 | `offline/src/emergency_enumerate.py` | `npm run offline` | ⚠️ re-run |
| Emergency reads, eMediBlock | 10,993, all recorded, 0 silent | same | same | ⚠️ re-run |
| Reads after revocation, eMediBlock | 0 | same | same | ⚠️ re-run |
| Administrator override, comparison | 20,412 reads, all silent, 9,079 after revocation | same | same | ⚠️ re-run |
| Eleven attacks, all defeated | 11/11 | `test/attacks/attack_suite.test.js` | `npm test` | ✅ runnable now |
| Static analysis score | 96.62 % | external tool (see below) | — | ⚠️ re-run |

**Static analysis.** The 96.62 % figure came from an automated scan. Re-run it
against the contracts in this repository and record the tool and version in the
paper; a score without a named tool is not checkable. `slither .` is the usual
choice for Solidity.

---

## Section 4.3 — Cost, resilience and interoperability

| Claim in the paper | Value stated | Produced by | Command | Status |
|---|---|---|---|---|
| Anchoring, unbatched | 96,449 gas per record | `bench/gas_anchor_batch.js` | `npx hardhat run bench/gas_anchor_batch.js` | ⚠️ re-measure |
| Anchoring, batched at B = 64 | 1,126 gas per record | same | same | ⚠️ re-measure |
| Batching latency cost | 2,402 gas at 1 min; 481 at 5 min | `offline/src/batch_latency.py` | `npm run offline` | ⚠️ re-run |
| Permission check, epoch design | 34,140 gas, constant | `bench/gas_access.js` | `npx hardhat run bench/gas_access.js` | ⚠️ re-measure |
| Permission check, list scan | 31,200 / 60,900 / 192,900 / 687,900 gas at 1 / 10 / 50 / 200 grants | same | same | ⚠️ re-measure |
| Crossover point | ≈ 5 grants | same | same | ⚠️ re-measure |
| Recovery, model vs Monte Carlo | max difference 0.016 over 2000 trials | `offline/src/erasure_recovery.py` | `npm run offline` | ⚠️ re-run |
| Recovery vs replication | +9.84 percentage points | same | same | ⚠️ re-run |
| Tamper detection | 1500 / 1500 | same | same | ⚠️ re-run |
| FHIR conversion | 2078 resources across 8 types, 0 errors | `offline/src/fhir_convert.py` | `npm run offline` | ⚠️ re-run |
| FHIR negative controls | 10 / 10 caught | `offline/src/fhir_validate.py` | same | ⚠️ re-run |
| Scheduler saving | 12.9 % at a 4 h deadline | `offline/src/scheduler_sim.py` | same | ⚠️ re-run |
| Offline (clairvoyant) bound | 29.1 % | same | same | ⚠️ re-run |
| Deadline violations | 0 | same | same | ⚠️ re-run |

---

## Section 5 — Discussion and limitations

Section 5 makes no new quantitative claims. Section 5.1 reports figures taken
from other authors' papers, which are cited rather than reproduced here; 5.2
states the limits of the evidence; 5.4 describes this repository.

---

## Figures

| Figure | Content | Produced by |
|---|---|---|
| 1 | Framework overview and modules | schematic, `figures/` |
| 2 | Deployment and participants | schematic, `figures/` |
| 3 | Architecture layers | schematic, `figures/` |
| 4 | Contract optimisation and cost per transaction | `results/contract_size.json`, `results/gas-report.txt` |
| 5 | Cost through the day | `offline/src/gasprice_model.py` |
| 6 | Emergency access | `offline/src/emergency_enumerate.py` |
| 7 | Surviving server failures | `offline/src/erasure_recovery.py` |
| 8 | Appointment allocation and record exchange | `offline/src/` |
| 9 | Scheduling routine transactions | `offline/src/scheduler_sim.py` |

`npm run figures` regenerates 4–9 from the raw output. Figures 1–3 are
schematics and are not generated from data.

---

## Checklist before resubmission

- [ ] `npm test` — all attacks green
- [ ] `npm run bench` — `results/results.json` written
- [ ] `npm run offline` — enumeration and offline experiments complete
- [ ] Every ⚠️ row above resolved: paper corrected to match measured output
- [ ] Commit id recorded in Boxes 1 and 2 of Section 3.9
- [ ] Repository public; URL inserted in Section 5.4 and the Code Availability Statement
- [ ] Release tagged and archived; DOI inserted
- [ ] Static analysis re-run, tool and version named in the paper
- [ ] `data/download_dataset.py` selection rule confirmed against what was actually used
