# results/

**These files are committed on purpose.** They are the evidence for the numbers
printed in the paper, and a reader who cannot run the code must still be able to
see what the runs produced.

| File | Produced by | Feeds |
|---|---|---|
| `contract_size.json` | `npx hardhat run bench/contract_size.js` | Section 4.1, contract optimisation |
| `gas_access.json` | `npx hardhat run bench/gas_access.js` | Section 4.3, checking permission |
| `gas_anchor_batch.json` | `npx hardhat run bench/gas_anchor_batch.js` | Section 4.3, cost of anchoring |
| `results.json` | `npm run bench` (merges the above) | every on-chain number in the paper |
| `gas-report.txt` | hardhat-gas-reporter, during `npm test` | supporting detail |

## The rule

Whatever these files say is what goes in the manuscript. If a figure in the
paper disagrees with a figure here, **the paper is wrong and must be corrected**
— not the other way round. Do not hand-edit anything in this directory.
