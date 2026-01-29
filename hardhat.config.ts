import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

/**
 * =============================================================================
 * HARDHAT CONFIGURATION
 * =============================================================================
 * 
 * This file configures the Hardhat development environment for FairWin contracts.
 * 
 * NETWORKS:
 * - hardhat: Local testing (default)
 * - mumbai: Polygon testnet for staging
 * - polygon: Polygon mainnet for production
 * 
 * ENVIRONMENT VARIABLES REQUIRED:
 * - PRIVATE_KEY: Your deployer wallet private key (keep secret!)
 * - POLYGONSCAN_API_KEY: For contract verification
 * - ALCHEMY_MUMBAI_URL: RPC endpoint for testnet
 * - ALCHEMY_POLYGON_URL: RPC endpoint for mainnet
 */

const config: HardhatUserConfig = {
  // Solidity compiler configuration
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200, // Optimize for average number of function calls
      },
      viaIR: true, // Enable IR-based code generation for better optimization
    },
  },

  // Network configurations
  networks: {
    // Local Hardhat network (used by default for testing)
    hardhat: {
      chainId: 31337,
      // Fork mainnet for realistic testing (optional)
      // forking: {
      //   url: process.env.ALCHEMY_POLYGON_URL || "",
      // },
    },

    // Polygon Mumbai Testnet
    mumbai: {
      url: process.env.ALCHEMY_MUMBAI_URL || "https://rpc-mumbai.maticvigil.com",
      chainId: 80001,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 35000000000, // 35 gwei
    },

    // Polygon Mainnet
    polygon: {
      url: process.env.ALCHEMY_POLYGON_URL || "https://polygon-rpc.com",
      chainId: 137,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
      gasPrice: 50000000000, // 50 gwei (adjust based on network conditions)
    },
  },

  // Etherscan/Polygonscan verification
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGONSCAN_API_KEY || "",
      polygonMumbai: process.env.POLYGONSCAN_API_KEY || "",
    },
  },

  // Gas reporter for optimization
  gasReporter: {
    enabled: process.env.REPORT_GAS === "true",
    currency: "USD",
    gasPrice: 50, // gwei
    coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  },

  // TypeScript paths
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
