require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

/**
 * Solidity 0.8.20, as stated in Section 3 of the manuscript.
 *
 * The optimizer settings below matter for the deployed-size and gas figures of
 * Section 4.1. If you change them, the numbers change, so re-run `npm run
 * bench` and update the paper rather than leaving the old figures in place.
 */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: { enabled: true, runs: 200 },
      evmVersion: "paris",
    },
  },
  networks: {
    hardhat: {
      // Deterministic local chain; every number in results/results.json that
      // is not marked "sepolia" comes from here.
      blockGasLimit: 30000000,
    },
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL || "",
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
    outputFile: "results/gas-report.txt",
    noColors: true,
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    artifacts: "./artifacts",
  },
};
