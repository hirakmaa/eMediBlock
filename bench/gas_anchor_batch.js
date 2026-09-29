/**
 * bench/gas_anchor_batch.js
 * ---------------------------------------------------------------------------
 * Section 4.3, "Cost" — batched anchoring.
 *
 * Measures the per-record cost of writing commitments to the chain two ways:
 *
 *   anchorSingle  - one transaction per record
 *   anchorBatch   - one transaction per batch of B records, each record still
 *                   individually provable via a Merkle inclusion proof
 *
 * The manuscript reports 96,449 gas per record unbatched, falling to 1,126 gas
 * per record at B = 64. As with gas_access.js, those figures came from an
 * earlier implementation: what this script prints is authoritative for the
 * contracts published here.
 *
 * The waiting time that batching costs is reported alongside the saving rather
 * than omitted — see offline/src/batch_latency.py for that half.
 */
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

const BATCH_SIZES = [1, 2, 4, 8, 16, 32, 64, 128];

/** Hash a pair in sorted order, matching EMediBlockAnchor._computeRoot. */
function hashPair(a, b) {
  const [x, y] = a.toLowerCase() <= b.toLowerCase() ? [a, b] : [b, a];
  return ethers.keccak256(ethers.concat([x, y]));
}

/** Build a Merkle root from leaves, duplicating the last leaf on odd levels. */
function merkleRoot(leaves) {
  if (leaves.length === 0) return ethers.ZeroHash;
  let level = [...leaves];
  while (level.length > 1) {
    const next = [];
    for (let i = 0; i < level.length; i += 2) {
      const left = level[i];
      const right = i + 1 < level.length ? level[i + 1] : level[i];
      next.push(hashPair(left, right));
    }
    level = next;
  }
  return level[0];
}

function proofFor(leaves, index) {
  const proof = [];
  let level = [...leaves];
  let idx = index;
  while (level.length > 1) {
    const next = [];
    for (let i = 0; i < level.length; i += 2) {
      const left = level[i];
      const right = i + 1 < level.length ? level[i + 1] : level[i];
      if (i === idx || i + 1 === idx) {
        proof.push(idx === i ? right : left);
      }
      next.push(hashPair(left, right));
    }
    idx = Math.floor(idx / 2);
    level = next;
  }
  return proof;
}

async function main() {
  const Anchor = await ethers.getContractFactory("EMediBlockAnchor");
  const anchor = await Anchor.deploy();
  await anchor.waitForDeployment();

  // ---- unbatched reference ------------------------------------------------
  let singleTotal = 0n;
  const SAMPLES = 8;
  for (let i = 0; i < SAMPLES; i++) {
    const c = ethers.keccak256(ethers.toUtf8Bytes("single-record-" + i));
    const r = await (await anchor.anchorSingle(c)).wait();
    singleTotal += r.gasUsed;
  }
  const singlePerRecord = Number(singleTotal / BigInt(SAMPLES));
  console.log(`anchorSingle: ${singlePerRecord} gas per record\n`);

  // ---- batched ------------------------------------------------------------
  const rows = [];
  for (const B of BATCH_SIZES) {
    const leaves = [];
    for (let i = 0; i < B; i++) {
      leaves.push(ethers.keccak256(ethers.toUtf8Bytes(`b${B}-record-${i}`)));
    }
    const root = merkleRoot(leaves);

    const receipt = await (await anchor.anchorBatch(root, B)).wait();
    const perRecord = Number(receipt.gasUsed) / B;

    // Confirm a single record is still provable from the batch root.
    const batchId = await anchor.batchCount();
    const proof = proofFor(leaves, 0);
    const ok = await anchor.verifyInclusion(batchId, leaves[0], proof);
    if (!ok) throw new Error(`inclusion proof failed at B=${B}`);

    rows.push({
      batch_size: B,
      batch_gas: Number(receipt.gasUsed),
      gas_per_record: Number(perRecord.toFixed(2)),
      proof_length: proof.length,
      inclusion_verified: ok,
    });

    console.log(
      `B=${String(B).padStart(4)}  total=${String(receipt.gasUsed).padStart(8)}  ` +
      `per-record=${perRecord.toFixed(2).padStart(10)}  proof=${proof.length} hashes`
    );
  }

  const out = {
    description:
      "Per-record cost of anchoring commitments, unbatched against batched, " +
      "with an inclusion proof verified at every batch size. Measured.",
    anchor_single_gas_per_record: singlePerRecord,
    rows,
    generated: new Date().toISOString(),
  };

  const dir = path.join(__dirname, "..", "results");
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(
    path.join(dir, "gas_anchor_batch.json"),
    JSON.stringify(out, null, 2)
  );
  console.log("\nwrote results/gas_anchor_batch.json");
}

main().catch((e) => { console.error(e); process.exitCode = 1; });
