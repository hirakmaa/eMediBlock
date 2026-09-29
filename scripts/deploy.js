/**
 * scripts/deploy.js — deploy the suite in dependency order and write the
 * addresses to results/deployment.json.
 *
 *   npx hardhat run scripts/deploy.js                  (local)
 *   npx hardhat run scripts/deploy.js --network sepolia
 */
const { ethers, network } = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log(`deploying as ${deployer.address} on ${network.name}`);

  const registry = await (await ethers.getContractFactory("EMediBlockRegistry")).deploy();
  await registry.waitForDeployment();

  const consent = await (await ethers.getContractFactory("EMediBlockConsent"))
    .deploy(await registry.getAddress());
  await consent.waitForDeployment();

  const anchor = await (await ethers.getContractFactory("EMediBlockAnchor")).deploy();
  await anchor.waitForDeployment();

  const emergency = await (await ethers.getContractFactory("EMediBlockEmergency"))
    .deploy(await registry.getAddress());
  await emergency.waitForDeployment();

  const recovery = await (await ethers.getContractFactory("EMediBlockRecovery"))
    .deploy(await registry.getAddress(), await consent.getAddress());
  await recovery.waitForDeployment();

  const mhr = await (await ethers.getContractFactory("MedicalHealthRecord")).deploy(
    await registry.getAddress(),
    await consent.getAddress(),
    await emergency.getAddress()
  );
  await mhr.waitForDeployment();

  const out = {
    network: network.name,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    addresses: {
      EMediBlockRegistry:  await registry.getAddress(),
      EMediBlockConsent:   await consent.getAddress(),
      EMediBlockAnchor:    await anchor.getAddress(),
      EMediBlockEmergency: await emergency.getAddress(),
      EMediBlockRecovery:  await recovery.getAddress(),
      MedicalHealthRecord: await mhr.getAddress(),
    },
  };

  fs.mkdirSync(path.join(__dirname, "..", "results"), { recursive: true });
  fs.writeFileSync(
    path.join(__dirname, "..", "results", "deployment.json"),
    JSON.stringify(out, null, 2)
  );
  console.table(out.addresses);
  console.log("wrote results/deployment.json");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
