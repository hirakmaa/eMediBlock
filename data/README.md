# data/

The experimental input for Section 4.1.

## Source

The healthcare dataset is publicly available and fully de-identified, published
by Imran MD (2024) — Reference **[27]** of the manuscript:

<https://github.com/imranbdcse/healthcaredatasets/blob/DataScience/healthcare_dataset.csv>

Because the dataset is openly published and de-identified, no additional ethical
approval or informed consent was required for its use.

## Reproducing the input

```bash
python3 data/download_dataset.py
```

This fetches the CSV into `data/raw/` (git-ignored — we do not redistribute
someone else's dataset), selects the 20 records used in the experiments, writes
`selected_20.csv`, and records checksums in `selection_manifest.json`.

## ⚠️ Confirm the selection rule

The manuscript states that 20 records were selected but not how they were
chosen. `download_dataset.py` implements an explicit rule — the first 20
complete rows in file order — so that the selection is reproducible. **If that
is not what you actually did, correct `SELECTION_RULE` in the script and
regenerate**, otherwise a reviewer will get a different 20 records and the 2078
FHIR resources reported in Section 4.3 will not reproduce.
