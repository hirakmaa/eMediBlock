# offline/

The experiments that do not need a chain: exhaustive enumeration of the consent
and emergency rules, the erasure-coding recovery model, the HL7 FHIR conversion
and validation, and the transaction scheduler.

## ⚠️ Not yet written

**These files do not exist yet.** This directory currently holds the
specification for them, not the code. The contracts, benchmarks and attack suite
in this repository are complete; the offline experiments are not, and the
manuscript's Section 4.2 and 4.3 numbers depend on them.

Either port your existing scripts in under these names, or write them to the
specification below. Do not tag a release until this notice is gone.

## What each file must do

| File | Produces | Specification |
|---|---|---|
| `src/consent_enumerate.py` | `results/consent_enumeration.json` | Model the consent rules as a state machine over 12 actions. Enumerate **every** action sequence up to depth 6 (12⁶ = 2,985,984), for both the epoch design and the list-scan baseline. Report, per design: sequences tried, violations found, and — for the ordering attack — the fraction of block orderings in which a read succeeds after withdrawal has begun, at 2, 3 and 4 doctors. |
| `src/emergency_enumerate.py` | `results/emergency_enumeration.json` | Same method, depth 7 (279,936 sequences), over the break-glass state machine and, for comparison, an administrator override. Report: emergency reads that succeeded, how many left a disclosure record, and how many occurred after revocation, for each design. |
| `src/erasure_recovery.py` | `results/recovery.json` | Reed–Solomon (k, n). Compare the closed form of Eq. (6b) against Monte Carlo over 2000 trials at four (k, n) settings and six per-server failure rates; report the largest absolute difference. Compare availability against plain replication **at equal storage cost**. Run 1500 tamper trials and report detection. |
| `src/fhir_convert.py` | `data/fhir/*.json` | Convert the selected records into HL7 FHIR R4 resources — patient, encounter, observation, medication request, consent, document reference, provenance, audit event. Compute the record commitment over the **RFC 8785 (JCS)** canonical serialisation, which is what makes the on-chain value checkable by other systems (contribution C5). |
| `src/fhir_validate.py` | `results/fhir.json` | Validate every generated resource structurally. Report resources, types and errors. **Also run the negative controls**: deliberately corrupt 10 resources and confirm all 10 are caught. A validator that finds nothing is only reassuring if it can find something. |
| `src/scheduler_sim.py` | `results/scheduler.json` | Generate transaction prices from Ethereum's published fee rule (EIP-1559), driven by a daily demand pattern with bursts. Delay routine transactions to the cheapest moment before their deadline; report the saving, the clairvoyant bound, the delay incurred, and deadline violations. **Consent withdrawals and clinical writes must never be deferred** — assert this, do not merely intend it. |
| `src/gasprice_model.py` | `results/gasprice.json` | Fit and evaluate Eqs. (7)–(8), the diurnal + volume + spike gas-price model. |
| `src/batch_latency.py` | `results/batch_latency.json` | The waiting time batching costs: per-document gas against permitted wait, at several arrival rates. Report alongside the saving, never instead of it. |
| `src/natstyle.py` | — | Shared plotting style. No in-panel titles; bold panel letters at one absolute figure height; framed legends placed by measurement; 600 dpi. |
| `src/collage.py` | — | Two-panel plates, composited **pixel-wise with PIL**. Do not composite through matplotlib: it resamples at figure DPI and softens low-resolution schematics. Flatten RGBA onto white with `alpha_composite` before converting — a plain `convert("RGB")` maps transparency to black. |

## Running

```bash
python3 -m pip install -r offline/requirements.txt
python3 offline/run_all.py
```

`run_all.py` should execute each script in order and merge its output into
`results/results.json` alongside the on-chain measurements.
