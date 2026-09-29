/**
 * bench/run_all.js - runs every on-chain benchmark and merges the output into
 * results/results.json, which is the single file the manuscript's numbers are
 * read from.
 */
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const STEPS = ["contract_size.js", "gas_access.js", "gas_anchor_batch.js"];
const RESULTS = path.join(__dirname, "..", "results");

for (const s of STEPS) {
  console.log(`\n=== ${s} ===`);
  execSync(`npx hardhat run ${path.join("bench", s)}`, { stdio: "inherit" });
}

const merged = { generated: new Date().toISOString(), onchain: {} };
for (const f of ["contract_size.json", "gas_access.json", "gas_anchor_batch.json"]) {
  const p = path.join(RESULTS, f);
  if (fs.existsSync(p)) {
    merged.onchain[f.replace(".json", "")] = JSON.parse(fs.readFileSync(p, "utf8"));
  }
}

const target = path.join(RESULTS, "results.json");
let existing = {};
if (fs.existsSync(target)) {
  try { existing = JSON.parse(fs.readFileSync(target, "utf8")); } catch (e) { existing = {}; }
}
fs.writeFileSync(target, JSON.stringify({ ...existing, ...merged }, null, 2));
console.log("\nwrote results/results.json");
