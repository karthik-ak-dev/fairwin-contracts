import { ethers, network } from "hardhat";

/**
 * FairWin Raffle Deployment Script
 * 
 * Usage:
 *   npx hardhat run scripts/deploy.ts --network <network>
 * 
 * Networks: localhost, mumbai, polygon
 */

// Network-specific addresses
const NETWORK_CONFIG: { [key: string]: { usdc: string; vrfCoordinator: string; keyHash: string } } = {
  // Polygon Mainnet
  polygon: {
    usdc: "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359",
    vrfCoordinator: "0xAE975071Be8F8eE67addBC1A82488F1C24858067",
    keyHash: "0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd"
  },
  // Polygon Amoy Testnet
  amoy: {
    usdc: "0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582", // Test USDC
    vrfCoordinator: "0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed",
    keyHash: "0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f"
  },
  // Local development
  localhost: {
    usdc: "", // Will be deployed
    vrfCoordinator: "", // Will be deployed
    keyHash: "0x0000000000000000000000000000000000000000000000000000000000000000"
  }
};

async function main() {
  const [deployer] = await ethers.getSigners();
  const networkName = network.name;
  
  console.log("=".repeat(60));
  console.log("FairWin Raffle Deployment");
  console.log("=".repeat(60));
  console.log(`Network: ${networkName}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH/MATIC`);
  console.log("=".repeat(60));

  let usdcAddress: string;
  let vrfCoordinatorAddress: string;
  let keyHash: string;
  let subscriptionId: bigint;

  if (networkName === "localhost" || networkName === "hardhat") {
    // Deploy mocks for local testing
    console.log("\n📦 Deploying mock contracts...");
    
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const mockUsdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    await mockUsdc.waitForDeployment();
    usdcAddress = await mockUsdc.getAddress();
    console.log(`  Mock USDC: ${usdcAddress}`);
    
    const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
    const mockVrf = await MockVRF.deploy();
    await mockVrf.waitForDeployment();
    vrfCoordinatorAddress = await mockVrf.getAddress();
    console.log(`  Mock VRF: ${vrfCoordinatorAddress}`);
    
    keyHash = NETWORK_CONFIG.localhost.keyHash;
    subscriptionId = 1n;
    
    // Mint some USDC to deployer for testing
    await mockUsdc.mint(deployer.address, ethers.parseUnits("100000", 6));
    console.log(`  Minted 100,000 USDC to deployer`);
    
  } else {
    // Use real addresses
    const config = NETWORK_CONFIG[networkName];
    if (!config) {
      throw new Error(`Unknown network: ${networkName}. Add config to NETWORK_CONFIG.`);
    }
    
    usdcAddress = config.usdc;
    vrfCoordinatorAddress = config.vrfCoordinator;
    keyHash = config.keyHash;
    
    // You need to create a subscription at https://vrf.chain.link
    // and set this value
    subscriptionId = BigInt(process.env.VRF_SUBSCRIPTION_ID || "0");
    
    if (subscriptionId === 0n) {
      console.log("\n⚠️  WARNING: VRF_SUBSCRIPTION_ID not set in .env");
      console.log("   Create one at https://vrf.chain.link and add this contract as consumer");
    }
    
    console.log(`\n📋 Using addresses:`);
    console.log(`  USDC: ${usdcAddress}`);
    console.log(`  VRF Coordinator: ${vrfCoordinatorAddress}`);
    console.log(`  VRF Subscription: ${subscriptionId}`);
  }

  // Deploy FairWinRaffle
  console.log("\n🚀 Deploying FairWinRaffle...");
  
  const FairWinRaffle = await ethers.getContractFactory("FairWinRaffle");
  const raffle = await FairWinRaffle.deploy(
    usdcAddress,
    vrfCoordinatorAddress,
    subscriptionId,
    keyHash
  );
  
  await raffle.waitForDeployment();
  const raffleAddress = await raffle.getAddress();
  
  console.log(`\n✅ FairWinRaffle deployed to: ${raffleAddress}`);
  
  // Summary
  console.log("\n" + "=".repeat(60));
  console.log("DEPLOYMENT SUMMARY");
  console.log("=".repeat(60));
  console.log(`Contract: ${raffleAddress}`);
  console.log(`Owner: ${deployer.address}`);
  console.log(`USDC: ${usdcAddress}`);
  console.log(`VRF Coordinator: ${vrfCoordinatorAddress}`);
  console.log(`VRF Subscription: ${subscriptionId}`);
  console.log("=".repeat(60));
  
  if (networkName !== "localhost" && networkName !== "hardhat") {
    console.log("\n📝 NEXT STEPS:");
    console.log("1. Add this contract as a consumer to your VRF subscription");
    console.log("   → https://vrf.chain.link");
    console.log("2. Fund your VRF subscription with LINK tokens");
    console.log("3. Verify contract on Polygonscan:");
    console.log(`   npx hardhat verify --network ${networkName} ${raffleAddress} \\`);
    console.log(`     ${usdcAddress} ${vrfCoordinatorAddress} ${subscriptionId} ${keyHash}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
