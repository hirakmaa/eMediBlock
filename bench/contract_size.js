/**
 * bench/contract_size.js
 * ---------------------------------------------------------------------------
 * Section 4.1, "Contract optimisation".
 *
 * Reports the deployed bytecode size of every contract in the suite, and the
 * gas consumed to deploy it as a percentage of the block gas limit.
 *
 * The manuscript states 124,131 bytes before optimisation and 106,130 after, a
 * 14.5 per cent reduction, with deployment gas falling from 68.88 to 37.56 per
 * cent of the block target. Those are historical figures from an earlier
 * implementation. Run this, and report what it prints.
 *
 * Note the EIP-170 limit: a single deployed contract may not exceed 24,576
 * bytes. A suite that reports six figures of "contract size" is reporting the
 * sum across contracts, or the creation bytecode, not one deployed runtime
 * object -- state which you mean in the paper.
 */
const { ethers, artifacts } = require("hardhat");
const fs = require("fs");
const path = require("path");

const NAMES = [
  "EMediBlockRegistry",
  "EMediBlockConsent",
  "EMediBlockAnchor",
  "EMediBlockEmergency",
  "EMediBlockRecovery",
  "MedicalHealthRecord",
];

const EIP170_LIMIT = 24576;

async function main() {
  const blockGasLimit = 30000000;
  const rows = [];
  let totalRuntime = 0;

  for (const name of NAMES) {
    const art = await artifacts.readArtifact(name);
    const runtime = (art.deployedBytecode.length - 2) / 2;   // strip 0x, 2 chars per byte
    const creation = (art.bytecode.length - 2) / 2;
    totalRuntime += runtime;

    rows.push({
      contract: name,
      deployed_bytes: runtime,
      creation_bytes: creation,
      eip170_headroom_bytes: EIP170_LIMIT - runtime,
      over_eip170_limit: runtime > EIP170_LIMIT,
    });

    console.log(
      `${name.padEnd(24)} deployed=${String(runtime).padStart(6)} B   ` +
      `creation=${String(creation).padStart(6)} B   ` +
      `headroom=${String(EIP170_LIMIT - runtime).padStart(6)} B`
    );
  }

  console.log(`\nsuite total (deployed): ${totalRuntime} B`);

  // Deployment gas, measured.
  console.log("\ndeployment gas:");
  const deployRows = [];
  const [admin] = await ethers.getSigners();

  const Registry = await ethers.getContractFactory("EMediBlockRegistry");
  const registry = await Registry.deploy();
  let r = await registry.deploymentTransaction().wait();
  deployRows.push({ contract: "EMediBlockRegistry", gas: Number(r.gasUsed) });

  const Consent = await ethers.getContractFactory("EMediBlockConsent");
  const consent = await Consent.deploy(await registry.getAddress());
  r = await consent.deploymentTransaction().wait();
  deployRows.push({ contract: "EMediBlockConsent", gas: Number(r.gasUsed) });

  const Anchor = await ethers.getContractFactory("EMediBlockAnchor");
  const anchor = await Anchor.deploy();
  r = await anchor.deploymentTransaction().wait();
  deployRows.push({ contract: "EMediBlockAnchor", gas: Number(r.gasUsed) });

  const Emergency = await ethers.getContractFactory("EMediBlockEmergency");
  const emergency = await Emergency.deploy(await registry.getAddress());
  r = await emergency.deploymentTransaction().wait();
  deployRows.push({ contract: "EMediBlockEmergency", gas: Number(r.gasUsed) });

  const Recovery = await ethers.getContractFactory("EMediBlockRecovery");
  const recovery = await Recovery.deploy(
    await registry.getAddress(), await consent.getAddress());
  r = await recovery.deploymentTransaction().wait();
  deployRows.push({ contract: "EMediBlockRecovery", gas: Number(r.gasUsed) });

  const MHR = await ethers.getContractFactory("MedicalHealthRecord");
  const mhr = await MHR.deploy(
    await registry.getAddress(),
    await consent.getAddress(),
    await emergency.getAddress());
  r = await mhr.deploymentTransaction().wait();
  deployRows.push({ contract: "MedicalHealthRecord", gas: Number(r.gasUsed) });

  let totalGas = 0;
  for (const d of deployRows) {
    d.percent_of_block_limit = Number(((d.gas / blockGasLimit) * 100).toFixed(2));
    totalGas += d.gas;
    console.log(
      `${d.contract.padEnd(24)} ${String(d.gas).padStart(9)} gas   ` +
      `${String(d.percent_of_block_limit).padStart(6)} % of block limit`
    );
  }

  const out = {
    description:
      "Deployed bytecode size and measured deployment gas for every contract " +
      "in the suite.",
    eip170_limit_bytes: EIP170_LIMIT,
    block_gas_limit: blockGasLimit,
    sizes: rows,
    deployment: deployRows,
    suite_total_deployed_bytes: totalRuntime,
    suite_total_deployment_gas: totalGas,
    suite_total_percent_of_block_limit:
      Number(((totalGas / blockGasLimit) * 100).toFixed(2)),
    generated: new Date().toISOString(),
  };

  fs.mkdirSync(path.join(__dirname, "..", "results"), { recursive: true });
  fs.writeFileSync(
    path.join(__dirname, "..", "results", "contract_size.json"),
    JSON.stringify(out, null, 2)
  );
  console.log("\nwrote results/contract_size.json");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
