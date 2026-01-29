const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("FairWinRaffle", function () {
  let raffle;
  let usdc;
  let vrfCoordinator;
  let owner;
  let user1, user2, user3, user4, user5;
  let users;
  
  // Constants matching contract
  const MAX_PLATFORM_FEE = 5;
  const MAX_WINNERS = 100;
  const MAX_WINNER_PERCENT = 50;
  const MIN_WINNER_PERCENT = 1;
  const MIN_ENTRY_PRICE = 10000; // $0.01
  const MIN_DURATION = 3600; // 1 hour
  const MAX_DURATION = 30 * 24 * 3600; // 30 days
  
  // Test values
  const ENTRY_PRICE = ethers.parseUnits("3", 6); // $3
  const DURATION = 24 * 3600; // 24 hours
  const WINNER_PERCENT = 10;
  const PLATFORM_FEE = 5;
  
  const SUBSCRIPTION_ID = 1;
  const KEY_HASH = "0xcc294a196eeeb44da2888d17c0625cc88d70d9760a69d58d853ba6581a9ab0cd";

  beforeEach(async function () {
    [owner, user1, user2, user3, user4, user5, ...users] = await ethers.getSigners();
    
    // Deploy mock USDC
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    usdc = await MockERC20.deploy("USD Coin", "USDC", 6);
    
    // Deploy mock VRF Coordinator
    const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
    vrfCoordinator = await MockVRF.deploy();
    
    // Deploy raffle contract
    const FairWinRaffle = await ethers.getContractFactory("FairWinRaffle");
    raffle = await FairWinRaffle.deploy(
      await usdc.getAddress(),
      await vrfCoordinator.getAddress(),
      SUBSCRIPTION_ID,
      KEY_HASH
    );
    
    // Mint USDC to users
    const mintAmount = ethers.parseUnits("10000", 6); // $10,000 each
    await usdc.mint(user1.address, mintAmount);
    await usdc.mint(user2.address, mintAmount);
    await usdc.mint(user3.address, mintAmount);
    await usdc.mint(user4.address, mintAmount);
    await usdc.mint(user5.address, mintAmount);
    
    // Approve raffle contract
    const raffleAddress = await raffle.getAddress();
    await usdc.connect(user1).approve(raffleAddress, mintAmount);
    await usdc.connect(user2).approve(raffleAddress, mintAmount);
    await usdc.connect(user3).approve(raffleAddress, mintAmount);
    await usdc.connect(user4).approve(raffleAddress, mintAmount);
    await usdc.connect(user5).approve(raffleAddress, mintAmount);
  });

  // =========================================================================
  // RAFFLE CREATION TESTS
  // =========================================================================
  
  describe("Raffle Creation", function () {
    it("Should create raffle with valid parameters", async function () {
      await expect(raffle.createRaffle(
        ENTRY_PRICE,
        DURATION,
        0, // unlimited entries
        WINNER_PERCENT,
        PLATFORM_FEE
      )).to.emit(raffle, "RaffleCreated");
      
      const raffleData = await raffle.getRaffle(1);
      expect(raffleData.entryPrice).to.equal(ENTRY_PRICE);
      expect(raffleData.winnerPercent).to.equal(WINNER_PERCENT);
      expect(raffleData.platformFeePercent).to.equal(PLATFORM_FEE);
      expect(raffleData.state).to.equal(0); // Active
    });
    
    it("Should reject fee > 5%", async function () {
      await expect(raffle.createRaffle(
        ENTRY_PRICE,
        DURATION,
        0,
        WINNER_PERCENT,
        6 // 6% fee - INVALID
      )).to.be.revertedWithCustomError(raffle, "InvalidPlatformFee");
    });
    
    it("Should reject winner percent > 50%", async function () {
      await expect(raffle.createRaffle(
        ENTRY_PRICE,
        DURATION,
        0,
        51, // 51% winners - INVALID
        PLATFORM_FEE
      )).to.be.revertedWithCustomError(raffle, "InvalidWinnerPercent");
    });
    
    it("Should reject winner percent < 1%", async function () {
      await expect(raffle.createRaffle(
        ENTRY_PRICE,
        DURATION,
        0,
        0, // 0% winners - INVALID
        PLATFORM_FEE
      )).to.be.revertedWithCustomError(raffle, "InvalidWinnerPercent");
    });
    
    it("Should reject entry price < $0.01", async function () {
      await expect(raffle.createRaffle(
        1000, // $0.001 - INVALID
        DURATION,
        0,
        WINNER_PERCENT,
        PLATFORM_FEE
      )).to.be.revertedWithCustomError(raffle, "InvalidEntryPrice");
    });
    
    it("Should reject duration < 1 hour", async function () {
      await expect(raffle.createRaffle(
        ENTRY_PRICE,
        1800, // 30 minutes - INVALID
        0,
        WINNER_PERCENT,
        PLATFORM_FEE
      )).to.be.revertedWithCustomError(raffle, "InvalidDuration");
    });
    
    it("Should only allow owner to create raffle", async function () {
      await expect(raffle.connect(user1).createRaffle(
        ENTRY_PRICE,
        DURATION,
        0,
        WINNER_PERCENT,
        PLATFORM_FEE
      )).to.be.revertedWithCustomError(raffle, "OwnableUnauthorizedAccount");
    });
  });

  // =========================================================================
  // ENTRY TESTS
  // =========================================================================
  
  describe("Raffle Entry", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 100, WINNER_PERCENT, PLATFORM_FEE);
    });
    
    it("Should allow valid entry", async function () {
      await expect(raffle.connect(user1).enterRaffle(1, 1))
        .to.emit(raffle, "RaffleEntered")
        .withArgs(1, user1.address, 1, 1, ENTRY_PRICE);
      
      const userEntry = await raffle.getUserEntry(1, user1.address);
      expect(userEntry.numEntries).to.equal(1);
    });
    
    it("Should transfer correct USDC amount", async function () {
      const balanceBefore = await usdc.balanceOf(user1.address);
      await raffle.connect(user1).enterRaffle(1, 5);
      const balanceAfter = await usdc.balanceOf(user1.address);
      
      expect(balanceBefore - balanceAfter).to.equal(ENTRY_PRICE * 5n);
    });
    
    it("Should reject entry after raffle ends", async function () {
      await time.increase(DURATION + 1);
      
      await expect(raffle.connect(user1).enterRaffle(1, 1))
        .to.be.revertedWithCustomError(raffle, "RaffleNotActive");
    });
    
    it("Should reject entry exceeding max entries per user", async function () {
      // Default max is 100
      await expect(raffle.connect(user1).enterRaffle(1, 101))
        .to.be.revertedWithCustomError(raffle, "ExceedsMaxEntriesPerUser");
    });
    
    it("Should reject entry exceeding max pool entries", async function () {
      // Max entries set to 100
      await raffle.connect(user1).enterRaffle(1, 50);
      await raffle.connect(user2).enterRaffle(1, 50);
      
      await expect(raffle.connect(user3).enterRaffle(1, 1))
        .to.be.revertedWithCustomError(raffle, "ExceedsMaxEntries");
    });
    
    it("Should NOT allow withdrawal after entry", async function () {
      await raffle.connect(user1).enterRaffle(1, 5);
      
      // No withdraw function exists - verify by checking ABI
      expect(raffle.withdraw).to.be.undefined;
      expect(raffle.withdrawEntry).to.be.undefined;
    });
  });

  // =========================================================================
  // DRAW TESTS
  // =========================================================================
  
  describe("Draw Mechanism", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      
      // Enter 100 users
      await raffle.connect(user1).enterRaffle(1, 25);
      await raffle.connect(user2).enterRaffle(1, 25);
      await raffle.connect(user3).enterRaffle(1, 25);
      await raffle.connect(user4).enterRaffle(1, 25);
    });
    
    it("Should not allow draw before end time", async function () {
      await expect(raffle.triggerDraw(1))
        .to.be.revertedWithCustomError(raffle, "RaffleStillActive");
    });
    
    it("Should trigger draw after end time", async function () {
      await time.increase(DURATION + 1);
      
      await expect(raffle.triggerDraw(1))
        .to.emit(raffle, "DrawTriggered");
      
      const raffleData = await raffle.getRaffle(1);
      expect(raffleData.state).to.equal(1); // Drawing
    });
    
    it("Should calculate correct number of winners (10% of 100 = 10)", async function () {
      await time.increase(DURATION + 1);
      await raffle.triggerDraw(1);
      
      const raffleData = await raffle.getRaffle(1);
      expect(raffleData.numWinners).to.equal(10);
    });
    
    it("Should cap winners at 100", async function () {
      // Create raffle with 10% winners
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, 10, PLATFORM_FEE);
      
      // Enter 1200 entries (10% = 120, should cap at 100)
      for (let i = 0; i < 12; i++) {
        await usdc.mint(users[i].address, ethers.parseUnits("1000", 6));
        await usdc.connect(users[i]).approve(await raffle.getAddress(), ethers.parseUnits("1000", 6));
        await raffle.connect(users[i]).enterRaffle(2, 100);
      }
      
      await time.increase(DURATION + 1);
      await raffle.triggerDraw(2);
      
      const raffleData = await raffle.getRaffle(2);
      expect(raffleData.numWinners).to.equal(100); // Capped
    });
    
    it("Should ensure minimum 1 winner", async function () {
      // Create raffle with 1% winners
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, 1, PLATFORM_FEE);
      
      // Enter only 5 entries (1% = 0.05, should be 1)
      await raffle.connect(user1).enterRaffle(2, 5);
      
      await time.increase(DURATION + 1);
      await raffle.triggerDraw(2);
      
      const raffleData = await raffle.getRaffle(2);
      expect(raffleData.numWinners).to.equal(1); // Minimum
    });
    
    it("Should only allow owner to trigger draw", async function () {
      await time.increase(DURATION + 1);
      
      await expect(raffle.connect(user1).triggerDraw(1))
        .to.be.revertedWithCustomError(raffle, "OwnableUnauthorizedAccount");
    });
  });

  // =========================================================================
  // VRF CALLBACK & PRIZE DISTRIBUTION TESTS
  // =========================================================================
  
  describe("Prize Distribution", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      
      // 100 entries = 10 winners
      await raffle.connect(user1).enterRaffle(1, 25);
      await raffle.connect(user2).enterRaffle(1, 25);
      await raffle.connect(user3).enterRaffle(1, 25);
      await raffle.connect(user4).enterRaffle(1, 25);
      
      await time.increase(DURATION + 1);
      await raffle.triggerDraw(1);
    });
    
    it("Should distribute prizes to winners", async function () {
      // Simulate VRF callback
      const randomWords = [];
      for (let i = 0; i < 10; i++) {
        randomWords.push(ethers.toBigInt(ethers.randomBytes(32)));
      }
      
      const raffleData = await raffle.getRaffle(1);
      await vrfCoordinator.fulfillRandomWords(raffleData.vrfRequestId, await raffle.getAddress(), randomWords);
      
      // Check raffle completed
      const updatedRaffle = await raffle.getRaffle(1);
      expect(updatedRaffle.state).to.equal(2); // Completed
      
      // Check winners received prizes
      const winners = await raffle.getWinners(1);
      expect(winners.length).to.equal(10);
    });
    
    it("Should calculate correct prize amounts (95% to winners)", async function () {
      const totalPool = ENTRY_PRICE * 100n; // $300
      const expectedPrizePool = totalPool * 95n / 100n; // $285
      const expectedPerWinner = expectedPrizePool / 10n; // $28.50
      
      const randomWords = Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32)));
      const raffleData = await raffle.getRaffle(1);
      await vrfCoordinator.fulfillRandomWords(raffleData.vrfRequestId, await raffle.getAddress(), randomWords);
      
      const updatedRaffle = await raffle.getRaffle(1);
      expect(updatedRaffle.prizePerWinner).to.equal(expectedPerWinner);
    });
    
    it("Should add correct protocol fee to collected fees", async function () {
      const totalPool = ENTRY_PRICE * 100n; // $300
      const expectedFee = totalPool * 5n / 100n; // $15
      
      const randomWords = Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32)));
      const raffleData = await raffle.getRaffle(1);
      await vrfCoordinator.fulfillRandomWords(raffleData.vrfRequestId, await raffle.getAddress(), randomWords);
      
      const fees = await raffle.protocolFeesCollected();
      expect(fees).to.be.gte(expectedFee); // >= because of rounding dust
    });
  });

  // =========================================================================
  // CANCELLATION & REFUND TESTS
  // =========================================================================
  
  describe("Cancellation & Refunds", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      await raffle.connect(user1).enterRaffle(1, 10);
      await raffle.connect(user2).enterRaffle(1, 5);
    });
    
    it("Should allow admin to cancel active raffle", async function () {
      await expect(raffle.cancelRaffle(1, "Test cancellation"))
        .to.emit(raffle, "RaffleCancelled")
        .withArgs(1, "Test cancellation");
      
      const raffleData = await raffle.getRaffle(1);
      expect(raffleData.state).to.equal(3); // Cancelled
    });
    
    it("Should allow refund after cancellation", async function () {
      await raffle.cancelRaffle(1, "Test");
      
      const balanceBefore = await usdc.balanceOf(user1.address);
      await raffle.connect(user1).claimRefund(1);
      const balanceAfter = await usdc.balanceOf(user1.address);
      
      expect(balanceAfter - balanceBefore).to.equal(ENTRY_PRICE * 10n);
    });
    
    it("Should NOT allow refund if raffle not cancelled", async function () {
      await expect(raffle.connect(user1).claimRefund(1))
        .to.be.revertedWithCustomError(raffle, "RaffleNotCancelled");
    });
    
    it("Should NOT allow double refund", async function () {
      await raffle.cancelRaffle(1, "Test");
      await raffle.connect(user1).claimRefund(1);
      
      await expect(raffle.connect(user1).claimRefund(1))
        .to.be.revertedWithCustomError(raffle, "RefundAlreadyClaimed");
    });
    
    it("Should auto-cancel if minimum entries not met", async function () {
      // Create new raffle, enter only 1 person
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      await raffle.connect(user1).enterRaffle(2, 1);
      
      await time.increase(DURATION + 1);
      
      // TriggerDraw should auto-cancel
      await raffle.triggerDraw(2);
      
      const raffleData = await raffle.getRaffle(2);
      expect(raffleData.state).to.equal(3); // Cancelled
    });
  });

  // =========================================================================
  // FEE WITHDRAWAL TESTS
  // =========================================================================
  
  describe("Fee Withdrawal", function () {
    it("Should allow owner to withdraw collected fees", async function () {
      // Complete a raffle first
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      await raffle.connect(user1).enterRaffle(1, 50);
      await raffle.connect(user2).enterRaffle(1, 50);
      
      await time.increase(DURATION + 1);
      await raffle.triggerDraw(1);
      
      // Fulfill VRF
      const raffleData = await raffle.getRaffle(1);
      const randomWords = Array(10).fill(0).map(() => ethers.toBigInt(ethers.randomBytes(32)));
      await vrfCoordinator.fulfillRandomWords(raffleData.vrfRequestId, await raffle.getAddress(), randomWords);
      
      // Withdraw fees
      const fees = await raffle.protocolFeesCollected();
      const balanceBefore = await usdc.balanceOf(owner.address);
      
      await raffle.withdrawFees(owner.address, fees);
      
      const balanceAfter = await usdc.balanceOf(owner.address);
      expect(balanceAfter - balanceBefore).to.equal(fees);
    });
    
    it("Should NOT allow withdrawing more than collected fees", async function () {
      await expect(raffle.withdrawFees(owner.address, ethers.parseUnits("1000", 6)))
        .to.be.revertedWithCustomError(raffle, "NoFeesToWithdraw");
    });
    
    it("Should NOT allow non-owner to withdraw", async function () {
      await expect(raffle.connect(user1).withdrawFees(user1.address, 1))
        .to.be.revertedWithCustomError(raffle, "OwnableUnauthorizedAccount");
    });
  });

  // =========================================================================
  // PAUSE TESTS
  // =========================================================================
  
  describe("Pause Functionality", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
    });
    
    it("Should prevent entries when paused", async function () {
      await raffle.pause();
      
      await expect(raffle.connect(user1).enterRaffle(1, 1))
        .to.be.revertedWithCustomError(raffle, "EnforcedPause");
    });
    
    it("Should allow refunds when paused", async function () {
      await raffle.connect(user1).enterRaffle(1, 5);
      await raffle.cancelRaffle(1, "Test");
      await raffle.pause();
      
      // Refunds should still work
      await expect(raffle.connect(user1).claimRefund(1))
        .to.emit(raffle, "RefundClaimed");
    });
    
    it("Should resume after unpause", async function () {
      await raffle.pause();
      await raffle.unpause();
      
      await expect(raffle.connect(user1).enterRaffle(1, 1))
        .to.emit(raffle, "RaffleEntered");
    });
  });

  // =========================================================================
  // VIEW FUNCTION TESTS
  // =========================================================================
  
  describe("View Functions", function () {
    beforeEach(async function () {
      await raffle.createRaffle(ENTRY_PRICE, DURATION, 0, WINNER_PERCENT, PLATFORM_FEE);
      await raffle.connect(user1).enterRaffle(1, 50);
      await raffle.connect(user2).enterRaffle(1, 50);
    });
    
    it("Should calculate expected winners correctly", async function () {
      const [expectedWinners, prizePerWinner] = await raffle.calculateExpectedWinners(1);
      
      expect(expectedWinners).to.equal(10); // 10% of 100
      
      const totalPool = ENTRY_PRICE * 100n;
      const prizePool = totalPool * 95n / 100n;
      expect(prizePerWinner).to.equal(prizePool / 10n);
    });
    
    it("Should report correct time remaining", async function () {
      const remaining = await raffle.getTimeRemaining(1);
      expect(remaining).to.be.closeTo(DURATION, 10);
      
      await time.increase(DURATION + 1);
      
      const remainingAfter = await raffle.getTimeRemaining(1);
      expect(remainingAfter).to.equal(0);
    });
    
    it("Should check if draw can be triggered", async function () {
      let [canDraw, reason] = await raffle.canTriggerDraw(1);
      expect(canDraw).to.be.false;
      expect(reason).to.equal("Raffle not ended yet");
      
      await time.increase(DURATION + 1);
      
      [canDraw, reason] = await raffle.canTriggerDraw(1);
      expect(canDraw).to.be.true;
      expect(reason).to.equal("Ready to draw");
    });
  });
});
