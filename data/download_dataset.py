#!/usr/bin/env python3
"""
data/download_dataset.py
===============================================================================
Fetches the healthcare dataset used in Section 4.1 and reproduces the 20-record
selection, so that the experimental input is obtained the same way every time
rather than being carried around as an undocumented copy.

Source (Reference [27] of the manuscript):
    https://github.com/imranbdcse/healthcaredatasets/blob/DataScience/healthcare_dataset.csv

The dataset is publicly available and fully de-identified; no additional
ethical approval or informed consent was required for its use. This is stated
in the Data Availability Statement of the manuscript.

-------------------------------------------------------------------------------
!! AUTHORS: ONE THING NEEDS YOUR CONFIRMATION !!

The manuscript says that 20 records were selected, but it does not say HOW.
This script therefore implements an explicit, deterministic rule -- the first
20 rows in file order after dropping rows with missing values in the fields the
FHIR conversion needs -- and records the checksum of what it produced.

If that is NOT the rule you actually used, change SELECTION_RULE below to match
what you did, re-run, and commit the result. A reviewer who reruns this must
land on the same 20 records you reported on, or the number 2078 in Section 4.3
will not reproduce.
-------------------------------------------------------------------------------
"""

import csv
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

RAW_URL = (
    "https://raw.githubusercontent.com/imranbdcse/healthcaredatasets/"
    "DataScience/healthcare_dataset.csv"
)

HERE = Path(__file__).resolve().parent
RAW_DIR = HERE / "raw"
RAW_CSV = RAW_DIR / "healthcare_dataset.csv"
SELECTED_CSV = HERE / "selected_20.csv"
MANIFEST = HERE / "selection_manifest.json"

N_RECORDS = 20

# Fields the FHIR conversion in offline/src/fhir_convert.py requires. A row
# missing any of these cannot be converted, so it is not eligible.
REQUIRED_FIELDS = [
    "Name",
    "Age",
    "Gender",
    "Blood Type",
    "Medical Condition",
    "Date of Admission",
    "Doctor",
    "Hospital",
    "Insurance Provider",
    "Billing Amount",
    "Room Number",
    "Admission Type",
    "Discharge Date",
    "Medication",
    "Test Results",
]

SELECTION_RULE = "first-20-complete-rows-in-file-order"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    if RAW_CSV.exists():
        print(f"already present: {RAW_CSV}")
        return
    print(f"downloading {RAW_URL}")
    try:
        urllib.request.urlretrieve(RAW_URL, RAW_CSV)
    except Exception as exc:                                   # noqa: BLE001
        sys.exit(
            f"\ndownload failed: {exc}\n\n"
            "If your network blocks raw.githubusercontent.com, fetch the file\n"
            "by hand from the URL in the manuscript's Data Availability\n"
            f"Statement and save it as:\n  {RAW_CSV}\n"
        )
    print(f"saved to {RAW_CSV}")


def select() -> None:
    with open(RAW_CSV, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        header = reader.fieldnames or []

        missing = [f for f in REQUIRED_FIELDS if f not in header]
        if missing:
            print(
                "WARNING: the upstream file does not carry these expected "
                f"columns: {missing}\n"
                "         The upstream repository may have changed. Check the "
                "column names before trusting the selection.",
                file=sys.stderr,
            )

        usable = [f for f in REQUIRED_FIELDS if f in header]
        chosen, scanned = [], 0
        for row in reader:
            scanned += 1
            if all(str(row.get(f, "")).strip() for f in usable):
                chosen.append(row)
                if len(chosen) == N_RECORDS:
                    break

    if len(chosen) < N_RECORDS:
        sys.exit(f"only {len(chosen)} complete rows found; expected {N_RECORDS}")

    with open(SELECTED_CSV, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=header)
        writer.writeheader()
        writer.writerows(chosen)

    manifest = {
        "source_url": RAW_URL,
        "reference": "[27] Imran MD (2024) Healthcare dataset. GitHub repository.",
        "selection_rule": SELECTION_RULE,
        "n_records": len(chosen),
        "rows_scanned": scanned,
        "raw_sha256": sha256_of(RAW_CSV),
        "selected_sha256": sha256_of(SELECTED_CSV),
        "required_fields": REQUIRED_FIELDS,
        "note": (
            "If the selection rule here does not match the one actually used "
            "for the published results, correct SELECTION_RULE in "
            "download_dataset.py and regenerate."
        ),
    }
    MANIFEST.write_text(json.dumps(manifest, indent=2))

    print(f"\nselected {len(chosen)} records -> {SELECTED_CSV}")
    print(f"raw sha256      {manifest['raw_sha256']}")
    print(f"selected sha256 {manifest['selected_sha256']}")
    print(f"manifest        {MANIFEST}")


if __name__ == "__main__":
    download()
    select()
