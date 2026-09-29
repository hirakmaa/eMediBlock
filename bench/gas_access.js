/**
 * bench/gas_access.js
 * ---------------------------------------------------------------------------
 * Section 4.3, "Checking permission".
 *
 * Measures the cost of the permission test as the number of grants a patient
 * has issued grows, for two designs:
 *
 *   eMediBlock  - EMediBlockConsent.canRead, constant-time epoch comparison
 *   baseline    - ConventionalConsent.canRead, scan over the grant list
 *
 * The manuscript reports 34,140 gas for the constant-time check against
 * 31,200 / 60,900 / 192,900 / 687,900 gas for the scan at 1 / 10 / 50 / 200
 * grants, with a crossover at about five grants. THOSE NUMBERS WERE PRODUCED BY
 * AN EARLIER IMPLEMENTATION. Whatever this script prints is what the published
 * contracts actually cost; if the two disagree, the paper must be corrected to
 * match this output, not the other way round.
 *
 * `canRead` is a view function, so it costs nothing to call off-chain. What is
 * measured here is the cost when it is called from within a transaction, which
 * is how a service actually uses it. GasProbe wraps both in a state-changing
 * function so the cost is observable in a receipt.
 */
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const GRANT_COUNTS = [1, 5, 10, 25, 50, 100, 200];
const RECORD_TYPE = ethers.encodeBytes32String("clinical-note");

async function main() {
  const signers = await ethers.getSigners();
  const [admin, patient] = signers;

  // A pool of grantees. Hardhat gives 20 accounts by default; beyond that we
  // use deterministic addresses, which is fine because only the patient and
  // the reader we actually measure need to be registered.
  const reader = signers[2];

  // ---- deploy -------------------------------------------------------------
  const Registry = await ethers.getContractFactory("EMediBlockRegistry");
  const registry = await Registry.deploy();
  await registry.waitForDeployment();

  const Consent = await ethers.getContractFactory("EMediBlockConsent");
  const consent = await Consent.deploy(await registry.getAddress());
  await consent.waitForDeployment();

  const Baseline = await ethers.getContractFactory("ConventionalConsent");
  const baseline = await Baseline.deploy();
  await baseline.waitForDeployment();

  const Probe = await ethers.getContractFactory("GasProbe");
  const probe = await Probe.deploy(
    await consent.getAddress(),
    await baseline.getAddress()
  );
  await probe.waitForDeployment();

  // ---- register -----------------------------------------------------------
  const ROLE = { None: 0, Patient: 1, Doctor: 2, Hospital: 3, Monitor: 4 };
  const hospital = signers[3];
  await registry.register(hospital.address, ROLE.Hospital, ethers.ZeroAddress);
  await registry.register(patient.address, ROLE.Patient, ethers.ZeroAddress);
  await registry.register(reader.address, ROLE.Doctor, hospital.address);

  // The reader's grant is made first, so it is present at every list length
  // and the scan has to walk past the others to reach it. Placing it last
  // would flatter the baseline.
  const epoch = await consent.currentEpoch(patient.address);
  await consent.connect(patient).grantConsent(reader.address, RECORD_TYPE, epoch);
  await baseline.connect(patient).grantConsent(reader.address, RECORD_TYPE);

  const rows = [];
  let filler = 0;

  for (const g of GRANT_COUNTS) {
    // Pad both designs out to g grants with distinct dummy grantees.
    while (filler < g - 1) {
      filler += 1;
      const dummy = ethers.getAddress(
        "0x" + (filler + 0x1000).toString(16).padStart(40, "0")
      );
      await registry.register(dummy, ROLE.Doctor, hospital.address);
      const e = await consent.currentEpoch(patient.address);
      await consent.connect(patient).grantConsent(dummy, RECORD_TYPE, e);
      await baseline.connect(patient).grantConsent(dummy, RECORD_TYPE);
    }

    const tx1 = await probe.probeEpoch(patient.address, reader.address, RECORD_TYPE);
    const r1 = await tx1.wait();

    const tx2 = await probe.probeBaseline(patient.address, reader.address, RECORD_TYPE);
    const r2 = await tx2.wait();

    rows.push({
      grants: g,
      emediblock_gas: Number(r1.gasUsed),
      baseline_gas: Number(r2.gasUsed),
    });

    console.log(
      `grants=${String(g).padStart(4)}  ` +
      `eMediBlock=${String(r1.gasUsed).padStart(8)}  ` +
      `baseline=${String(r2.gasUsed).padStart(8)}`
    );
  }

  // ---- crossover ----------------------------------------------------------
  let crossover = null;
  for (const r of rows) {
    if (r.baseline_gas >= r.emediblock_gas) { crossover = r.grants; break; }
  }

  const out = {
    description:
      "Gas cost of the permission test as a function of the number of grants " +
      "a patient has issued. Measured, not estimated.",
    record_type: "clinical-note",
    rows,
    crossover_grants: crossover,
    note:
      "Below the crossover the list scan is cheaper, because it does less work " +
      "when there is almost nothing to scan. This is reported rather than hidden.",
    generated: new Date().toISOString(),
  };

  const dir = path.join(__dirname, "..", "results");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "gas_access.json"),
    JSON.stringify(out, null, 2)
  );
  console.log("\nwrote results/gas_access.json");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
