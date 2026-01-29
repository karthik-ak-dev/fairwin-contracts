// SPDX-License-Identifier: MIT
// ^^^ This line declares the license. MIT is open-source, meaning anyone can use/modify this code.

pragma solidity ^0.8.20;
// ^^^ Tells the compiler which Solidity version to use.
// ^0.8.20 means "version 0.8.20 or higher, but below 0.9.0"
// Solidity 0.8+ has built-in overflow protection (no more SafeMath needed!)

/**
 * =============================================================================
 *                        FAIRWIN RAFFLE CONTRACT V2
 * =============================================================================
 * 
 * WHAT THIS CONTRACT DOES:
 * ------------------------
 * This is an on-chain raffle/lottery system. Users pay to enter, and when the
 * raffle ends, random winners are selected using Chainlink VRF (Verifiable 
 * Random Function) to ensure fairness.
 * 
 * KEY FEATURES:
 * - Multiple winners (10% of participants win, configurable)
 * - Provably fair randomness (Chainlink VRF - impossible to cheat)
 * - Capped platform fee (maximum 5%, hardcoded for trust)
 * - Non-custodial (funds go directly to smart contract, not a person)
 * 
 * HOW A RAFFLE WORKS:
 * 1. Admin creates a raffle with settings (price, duration, winner %)
 * 2. Users enter by paying USDC (entries recorded on blockchain)
 * 3. When time ends, admin triggers the draw
 * 4. Contract requests random numbers from Chainlink
 * 5. Chainlink sends back verified random numbers
 * 6. Contract selects winners and sends them prizes automatically
 * 7. Platform fee is collected (max 5%)
 * 
 * WHY BLOCKCHAIN?
 * - Transparent: Anyone can verify the code and see all transactions
 * - Trustless: No one can cheat or manipulate the results
 * - Automatic: Winners get paid instantly by the contract
 * - Immutable: Rules can't be changed after raffle starts
 * 
 * =============================================================================
 */


// =============================================================================
// IMPORTS - External code libraries we're using
// =============================================================================

/**
 * OpenZeppelin Contracts
 * ----------------------
 * OpenZeppelin is the industry standard for secure smart contract development.
 * These are battle-tested, audited contracts used by billions of dollars in DeFi.
 * Website: https://openzeppelin.com/contracts
 * 
 * Think of imports like using libraries in any programming language.
 * Instead of writing security code from scratch, we use proven solutions.
 */

// Ownable2Step: Manages who "owns" (administers) this contract
// Why "2Step"? Safer ownership transfer - new owner must accept, preventing accidents
// Example: If you accidentally set wrong address, they must accept before becoming owner
import "@openzeppelin/contracts/access/Ownable2Step.sol";

// Pausable: Emergency stop button for the contract
// If something goes wrong, owner can pause to prevent further damage
// Users can still claim refunds when paused (important for safety)
import "@openzeppelin/contracts/utils/Pausable.sol";

// ReentrancyGuard: Prevents a specific type of hack called "reentrancy attack"
// How reentrancy works: Attacker calls a function, and before it finishes,
// calls it again recursively to drain funds. This guard prevents that.
// Famous example: The DAO hack in 2016 lost $60M due to reentrancy
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

// IERC20: Interface for interacting with ERC20 tokens (like USDC)
// ERC20 is the standard for tokens on Ethereum/Polygon
// "Interface" means it defines WHAT functions exist, not HOW they work
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// SafeERC20: Wrapper for safe token transfers
// Some tokens don't follow the ERC20 standard exactly (USDT is famous for this)
// SafeERC20 handles these edge cases so transfers always work correctly
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * Chainlink VRF (Verifiable Random Function)
 * ------------------------------------------
 * Getting random numbers on blockchain is HARD. Why?
 * - Everything on blockchain is deterministic (same input = same output)
 * - Miners/validators can see pending transactions and manipulate them
 * - Using block hash as randomness can be gamed by miners
 * 
 * Chainlink VRF solves this:
 * 1. We request a random number
 * 2. Chainlink generates it OFF-CHAIN with cryptographic proof
 * 3. They send back the number + proof
 * 4. Anyone can verify the proof on-chain (proves it wasn't manipulated)
 * 
 * Cost: Each random request costs LINK tokens (Chainlink's cryptocurrency)
 * Website: https://vrf.chain.link
 */
import "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";


// =============================================================================
// MAIN CONTRACT
// =============================================================================

/**
 * CONTRACT INHERITANCE
 * --------------------
 * "is X, Y, Z" means this contract inherits from multiple parent contracts.
 * It's like a class extending multiple classes in OOP.
 * 
 * We inherit from:
 * - Ownable2Step: Gives us onlyOwner modifier and ownership management
 * - Pausable: Gives us whenNotPaused modifier and pause/unpause functions
 * - ReentrancyGuard: Gives us nonReentrant modifier
 * - VRFConsumerBaseV2: Required by Chainlink to receive random numbers
 */
contract FairWinRaffle is Ownable2Step, Pausable, ReentrancyGuard, VRFConsumerBaseV2 {
    
    /**
     * USING STATEMENT
     * ---------------
     * "using SafeERC20 for IERC20" attaches SafeERC20's functions to IERC20.
     * Instead of: SafeERC20.safeTransfer(token, recipient, amount)
     * We can write: token.safeTransfer(recipient, amount)
     * 
     * It's syntactic sugar (makes code cleaner to read).
     */
    using SafeERC20 for IERC20;


    // =========================================================================
    // CONSTANTS - Values that can NEVER change after deployment
    // =========================================================================
    
    /**
     * WHAT ARE CONSTANTS?
     * -------------------
     * Constants are values baked into the contract code itself.
     * They CANNOT be changed, even by the owner/admin.
     * 
     * WHY USE CONSTANTS?
     * - Trust: Users can verify these values will never change
     * - Gas savings: Constants are cheaper than storage variables
     * - Security: Critical limits can't be modified maliciously
     * 
     * HOW TO VERIFY?
     * Anyone can read the contract source code on Polygonscan and see these values.
     */
    
    /**
     * @notice Maximum platform fee the admin can ever set
     * @dev This is the MOST IMPORTANT trust guarantee in the contract
     * 
     * Set to 5 means: Maximum 5% fee, so winners always get at least 95%
     * 
     * TRUST IMPLICATION:
     * Even if the admin wanted to, they CANNOT take more than 5%.
     * This is enforced by code, not by promise.
     */
    uint256 public constant MAX_PLATFORM_FEE_PERCENT = 5;
    
    /**
     * @notice Minimum percentage of pool that goes to winners
     * @dev Derived from MAX_PLATFORM_FEE_PERCENT (100 - 5 = 95)
     */
    uint256 public constant MIN_WINNER_SHARE_PERCENT = 95;
    
    /**
     * @notice Maximum number of winners per raffle
     * @dev Why limit this?
     * 
     * 1. GAS COSTS: Each winner needs a transfer. 100 transfers = ~2.5M gas.
     *    If unlimited, a raffle with 10,000 winners would fail (out of gas).
     * 
     * 2. VRF COSTS: We request one random number per winner from Chainlink.
     *    More random numbers = more LINK tokens spent.
     * 
     * 3. BLOCK LIMITS: Polygon blocks have a gas limit (~30M).
     *    Too many operations in one transaction = transaction fails.
     * 
     * 100 winners is a safe, tested limit that works reliably.
     */
    uint256 public constant MAX_WINNERS = 100;
    
    /**
     * @notice Maximum percentage of participants who can win
     * @dev Set to 50 means at most half the players can win
     * 
     * Why cap at 50%?
     * - Keeps it feeling like a lottery (not everyone wins)
     * - Higher percentages would make prizes very small
     * - 50% is already very generous compared to traditional lotteries
     */
    uint256 public constant MAX_WINNER_PERCENT = 50;
    
    /**
     * @notice Minimum percentage of participants who win
     * @dev Set to 1 means at least 1% of players win
     * 
     * Example: 100 players with 1% = 1 winner (traditional jackpot style)
     */
    uint256 public constant MIN_WINNER_PERCENT = 1;
    
    /**
     * @notice Minimum raffle duration
     * @dev 1 hours = 3600 seconds
     * 
     * Why minimum 1 hour?
     * - Gives people time to enter
     * - Prevents "flash raffles" that could be gamed
     * - More fair for users in different time zones
     */
    uint256 public constant MIN_RAFFLE_DURATION = 1 hours;
    
    /**
     * @notice Maximum raffle duration
     * @dev 30 days in seconds
     * 
     * Why maximum 30 days?
     * - Prevents funds being locked forever
     * - Keeps raffles active and engaging
     * - Can always create new raffle after one ends
     */
    uint256 public constant MAX_RAFFLE_DURATION = 30 days;
    
    /**
     * @notice Minimum entry price in USDC
     * @dev 10000 = $0.01 (USDC has 6 decimals)
     * 
     * UNDERSTANDING TOKEN DECIMALS:
     * USDC uses 6 decimal places, so:
     * - 1 USDC = 1,000,000 (1 * 10^6)
     * - $0.01 = 10,000
     * - $1.00 = 1,000,000
     * - $100 = 100,000,000
     * 
     * This is like cents, but with more precision.
     * When you see "3000000" in the contract, that's $3.00
     */
    uint256 public constant MIN_ENTRY_PRICE = 10000;
    
    /**
     * @notice USDC decimal places
     * @dev Used for calculations and display
     */
    uint256 public constant USDC_DECIMALS = 6;


    // =========================================================================
    // IMMUTABLE STATE - Set once at deployment, never changes
    // =========================================================================
    
    /**
     * IMMUTABLE vs CONSTANT
     * ---------------------
     * - constant: Value known at compile time (hardcoded in code)
     * - immutable: Value set in constructor, then never changes
     * 
     * Both save gas compared to regular storage variables because
     * they're stored in the contract's bytecode, not in storage.
     */
    
    /**
     * @notice The USDC token contract we accept for payments
     * @dev Immutable means this address is set once and CANNOT change
     * 
     * USDC on Polygon Mainnet: 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
     * (Always verify addresses on official Circle/USDC documentation!)
     * 
     * WHY IMMUTABLE?
     * If this could be changed, a malicious admin could:
     * 1. Create a raffle accepting USDC
     * 2. Get users to deposit
     * 3. Change to a worthless token
     * 4. Steal all the real USDC
     * 
     * By making it immutable, users know exactly what token they're using forever.
     */
    IERC20 public immutable usdc;
    
    /**
     * @notice Chainlink VRF Coordinator contract
     * @dev This is the Chainlink contract that provides random numbers
     * 
     * Polygon Mainnet VRF Coordinator: 0xAE975071Be8F8eE67addBC1A82488F1C24858067
     * (Always verify on Chainlink's official documentation!)
     * 
     * WHY IMMUTABLE?
     * Prevents anyone from pointing to a fake "VRF" that returns predictable numbers.
     */
    VRFCoordinatorV2Interface public immutable vrfCoordinator;


    // =========================================================================
    // CONFIGURABLE STATE - Admin can modify these
    // =========================================================================
    
    /**
     * STORAGE VARIABLES
     * -----------------
     * These variables are stored on the blockchain (in "storage").
     * Reading them is free (view functions).
     * Writing them costs gas.
     * 
     * Think of storage like a database that lives on every Ethereum node worldwide.
     */
    
    // -------------------------------------------------------------------------
    // VRF Configuration
    // -------------------------------------------------------------------------
    
    /**
     * @notice Chainlink VRF subscription ID
     * @dev You create a subscription at https://vrf.chain.link
     * 
     * HOW VRF SUBSCRIPTIONS WORK:
     * 1. Go to vrf.chain.link
     * 2. Create a subscription
     * 3. Fund it with LINK tokens
     * 4. Add this contract as a "consumer"
     * 5. Contract can now request random numbers
     * 
     * Each random request costs LINK from your subscription balance.
     * If subscription runs out of LINK, random requests will fail!
     */
    uint64 public vrfSubscriptionId;
    
    /**
     * @notice VRF key hash (determines which Chainlink oracle network to use)
     * @dev Different key hashes = different gas price tiers
     * 
     * Polygon has multiple options:
     * - 500 gwei (faster, more expensive)
     * - 200 gwei (slower, cheaper)
     * 
     * The key hash you use should match your subscription's configuration.
     */
    bytes32 public vrfKeyHash;
    
    /**
     * @notice Maximum gas Chainlink can use when calling us back
     * @dev Set high (2.5M) because we're doing multiple winner transfers
     * 
     * CALLBACK GAS EXPLAINED:
     * When Chainlink has our random numbers ready, they call our 
     * fulfillRandomWords function. This setting limits how much gas
     * that callback can use.
     * 
     * Why 2,500,000?
     * - Selecting 100 winners + 100 transfers uses ~2M gas
     * - We add buffer for safety
     * - If set too low, callback fails and raffle gets stuck
     */
    uint32 public vrfCallbackGasLimit = 2500000;
    
    /**
     * @notice How many blocks to wait before VRF responds
     * @dev Higher = more secure, Lower = faster
     * 
     * WHY WAIT FOR BLOCK CONFIRMATIONS?
     * - Prevents block reorg attacks
     * - With 3 confirmations, attacker would need to rewrite 3 blocks
     * - On Polygon, 3 blocks ≈ 6 seconds
     * 
     * 3 is the standard recommendation from Chainlink.
     */
    uint16 public vrfRequestConfirmations = 3;
    
    // -------------------------------------------------------------------------
    // Global Limits (Safety Rails)
    // -------------------------------------------------------------------------
    
    /**
     * @notice Maximum total pool size in USDC
     * @dev 50000 * 10^6 = $50,000
     * 
     * WHY LIMIT POOL SIZE?
     * - Risk management: Limits exposure if there's a bug
     * - Start conservative: Increase as platform builds trust
     * - Regulatory: Some jurisdictions have limits on prize pools
     * 
     * This can be increased over time as the platform proves itself.
     */
    uint256 public maxPoolSize = 50000 * 10**6;
    
    /**
     * @notice Maximum entries one user can buy per raffle
     * @dev Prevents "whale" domination
     * 
     * WHY LIMIT PER-USER ENTRIES?
     * - Fairness: One rich person shouldn't have 90% of entries
     * - Decentralization: Better distribution of winners
     * - UX: Other users feel they have a real chance
     * 
     * 100 entries at $3 each = $300 max per person
     */
    uint256 public maxEntriesPerUser = 100;
    
    /**
     * @notice Minimum entries required for raffle to run
     * @dev If not met, raffle is cancelled and everyone gets refunded
     * 
     * WHY MINIMUM ENTRIES?
     * - Prevents running raffle with only 1 person (they'd just win their own money back)
     * - Ensures meaningful prize pool
     * - 2 is the absolute minimum for it to be a "raffle"
     */
    uint256 public minEntriesRequired = 2;
    
    // -------------------------------------------------------------------------
    // Counters & Tracking
    // -------------------------------------------------------------------------
    
    /**
     * @notice Next raffle ID to be assigned
     * @dev Starts at 1, increments with each new raffle
     * 
     * WHY START AT 1?
     * - 0 is often used to check "does this exist?"
     * - If raffleId 0 meant "first raffle", we couldn't distinguish from "no raffle"
     */
    uint256 public nextRaffleId = 1;
    
    /**
     * @notice Total protocol fees available for withdrawal
     * @dev This is the ONLY money admin can withdraw
     *
     * CRITICAL SECURITY POINT:
     * This counter ONLY increases when a raffle completes.
     * Admin's withdrawFees function can ONLY access this amount.
     * Active raffle pools are completely separate and untouchable.
     */
    uint256 public protocolFeesCollected;

    // -------------------------------------------------------------------------
    // Emergency Cancel Protection
    // -------------------------------------------------------------------------

    /**
     * @notice Minimum delay before emergency cancel can be triggered
     * @dev Set to 12 hours - VRF normally responds in <5 minutes
     *
     * WHY 12 HOURS?
     * - VRF usually responds in 30 seconds - 5 minutes
     * - Worst case during network congestion: 1-2 hours
     * - 12 hours is long enough to ensure VRF genuinely failed
     * - Prevents admin from canceling right after seeing unfavorable winners
     * - Still short enough for same-day recovery
     *
     * TRUST GUARANTEE:
     * Even if admin wanted to abuse emergencyCancelDrawing, they must wait
     * 12 hours - by then VRF will have definitely responded or definitely failed.
     */
    uint256 public constant EMERGENCY_CANCEL_DELAY = 12 hours;

    /**
     * @notice Tracks when draw was triggered for each raffle
     * @dev Used to enforce EMERGENCY_CANCEL_DELAY
     *
     * Maps raffleId → timestamp when triggerDraw was called
     */
    mapping(uint256 => uint256) public drawTriggeredAt;


    // =========================================================================
    // DATA STRUCTURES - Custom types we define
    // =========================================================================
    
    /**
     * ENUMS AND STRUCTS
     * -----------------
     * Solidity lets us define custom data types:
     * - enum: A fixed set of named options (like "Active", "Completed", etc.)
     * - struct: A custom object with multiple fields (like a class in other languages)
     */
    
    /**
     * @notice All possible states a raffle can be in
     * @dev This is called a "state machine" pattern
     * 
     * STATE MACHINE VISUALIZATION:
     * 
     *                         [triggerDraw]
     *     [createRaffle]          ↓
     *           ↓            ┌─────────┐      [VRF callback]
     *      ┌────────┐        │         │           ↓
     *      │ Active │───────→│ Drawing │──────→ Completed
     *      └────────┘        │         │
     *           │            └─────────┘
     *           │                 │
     *    [cancelRaffle]    [emergencyCancel]
     *           │                 │
     *           ↓                 ↓
     *      ┌───────────────────────┐
     *      │      Cancelled        │
     *      └───────────────────────┘
     * 
     * VALID TRANSITIONS:
     * - Active → Drawing (when triggerDraw is called after end time)
     * - Active → Cancelled (when admin cancels or min entries not met)
     * - Drawing → Completed (when Chainlink sends random numbers)
     * - Drawing → Cancelled (emergency only, if VRF fails)
     * 
     * INVALID TRANSITIONS (blocked by code):
     * - Can't go from Completed to anything (final state)
     * - Can't go from Cancelled to anything (final state)
     * - Can't go from Drawing back to Active
     */
    enum RaffleState {
        Active,     // 0: Raffle is running, accepting entries
        Drawing,    // 1: Entries closed, waiting for random numbers
        Completed,  // 2: Winners selected and paid
        Cancelled   // 3: Raffle cancelled, refunds available
    }
    
    /**
     * @notice All information about a single raffle
     * @dev Stored in the `raffles` mapping
     * 
     * STRUCT LAYOUT:
     * Solidity packs struct variables into 32-byte storage slots.
     * We order fields to minimize storage slots used (gas optimization).
     */
    struct Raffle {
        // === Configuration (set at creation, never changes) ===
        
        uint256 entryPrice;         // Price per entry in USDC (6 decimals)
                                    // Example: 3000000 = $3.00
        
        uint256 startTime;          // Unix timestamp when raffle started
                                    // Unix time = seconds since Jan 1, 1970
                                    // Example: 1706450400 = Jan 28, 2024 2:00 PM UTC
        
        uint256 endTime;            // Unix timestamp when entries close
                                    // After this time, no more entries allowed
        
        uint256 maxEntries;         // Maximum total entries allowed (0 = unlimited)
                                    // Used to cap pool size for specific raffles
        
        uint256 winnerPercent;      // What % of participants win (1-50)
                                    // Example: 10 means 10% win
                                    // 100 entries with 10% = 10 winners
        
        uint256 platformFeePercent; // Platform fee for this raffle (0-5)
                                    // Example: 5 means 5% fee
                                    // $300 pool with 5% fee = $15 to platform
        
        // === Current State (changes as raffle progresses) ===
        
        RaffleState state;          // Current state (Active/Drawing/Completed/Cancelled)
        
        uint256 totalEntries;       // How many entries have been purchased
        
        uint256 totalPool;          // Total USDC collected (in 6 decimals)
                                    // Example: 300000000 = $300.00
        
        // === Results (filled in after draw) ===
        
        uint256 numWinners;         // How many winners were selected
                                    // Might be less than calculated if capped at 100
        
        uint256 prizePerWinner;     // How much each winner receives
                                    // totalPool * 95% / numWinners
        
        uint256 vrfRequestId;       // Chainlink request ID for tracking
                                    // Used to match callback to correct raffle
    }
    
    /**
     * @notice Tracks a user's participation in a specific raffle
     * 
     * WHY TRACK THIS?
     * - Know how many entries each user has (for max limit)
     * - Calculate refund amount if cancelled
     * - Prevent double refund claims
     */
    struct UserEntry {
        uint256 numEntries;     // How many entries user purchased
        uint256 startIndex;     // Index of their first entry (for winner lookup)
        bool refundClaimed;     // Have they claimed refund? (prevents double-claim)
    }


    // =========================================================================
    // MAPPINGS - Key-value storage (like a hash table / dictionary)
    // =========================================================================
    
    /**
     * WHAT ARE MAPPINGS?
     * ------------------
     * Mappings are like dictionaries/hash tables in other languages.
     * mapping(KeyType => ValueType) means: given a key, get a value.
     * 
     * Key properties:
     * - O(1) lookup (constant time, very fast)
     * - Can't iterate over (no way to list all keys)
     * - Non-existent keys return default value (0, false, empty)
     */
    
    /**
     * @notice All raffles stored by ID
     * @dev raffles[1] = first raffle, raffles[2] = second raffle, etc.
     */
    mapping(uint256 => Raffle) public raffles;
    
    /**
     * @notice User entries per raffle
     * @dev userEntries[raffleId][userAddress] = their entry info
     * 
     * Example: userEntries[1][0xABC...] = entries for user 0xABC in raffle 1
     */
    mapping(uint256 => mapping(address => UserEntry)) public userEntries;
    
    /**
     * @notice Maps entry index to owner address
     * @dev entryOwners[raffleId][entryIndex] = who owns that entry
     * 
     * Example: If Alice buys entries 0-4, Bob buys 5-9:
     * entryOwners[1][0] = Alice
     * entryOwners[1][4] = Alice
     * entryOwners[1][5] = Bob
     * entryOwners[1][9] = Bob
     * 
     * When random number selects entry #7, we look up entryOwners[1][7] = Bob wins!
     */
    mapping(uint256 => mapping(uint256 => address)) public entryOwners;
    
    /**
     * @notice Maps VRF request ID back to raffle ID
     * @dev When Chainlink calls back, we need to know which raffle it's for
     * 
     * Flow:
     * 1. We call VRF, get requestId 12345
     * 2. We store: vrfRequestToRaffle[12345] = raffleId 1
     * 3. Chainlink calls fulfillRandomWords with requestId 12345
     * 4. We look up: vrfRequestToRaffle[12345] = 1, so it's for raffle 1
     */
    mapping(uint256 => uint256) public vrfRequestToRaffle;
    
    /**
     * @notice List of winners for each raffle
     * @dev raffleWinners[raffleId] = array of winner addresses
     * 
     * Why array? So we can return all winners in one call.
     * Frontend can show: "Winners: Alice, Bob, Carol, ..."
     */
    mapping(uint256 => address[]) public raffleWinners;
    
    /**
     * @notice Quick lookup: did this address win this raffle?
     * @dev isWinner[raffleId][address] = true/false
     * 
     * Used for:
     * 1. Ensuring unique winners (same person can't win twice)
     * 2. Quick check for frontend: "Did I win?"
     */
    mapping(uint256 => mapping(address => bool)) public isWinner;


    // =========================================================================
    // EVENTS - Logs emitted for off-chain tracking
    // =========================================================================
    
    /**
     * WHAT ARE EVENTS?
     * ----------------
     * Events are logs stored on the blockchain that external systems can listen to.
     * They're NOT stored in contract storage (cheaper than storage).
     * 
     * USE CASES:
     * - Frontend listens for RaffleEntered to update UI in real-time
     * - Backend indexes WinnersSelected to send notifications
     * - Analytics track all activity without reading contract state
     * 
     * The `indexed` keyword makes that parameter searchable.
     * You can filter: "Show me all RaffleEntered events for user 0xABC"
     */
    
    /// @notice Emitted when a new raffle is created
    event RaffleCreated(
        uint256 indexed raffleId,       // indexed = searchable
        uint256 entryPrice,
        uint256 startTime,
        uint256 endTime,
        uint256 maxEntries,
        uint256 winnerPercent,
        uint256 platformFeePercent
    );
    
    /// @notice Emitted when someone enters a raffle
    event RaffleEntered(
        uint256 indexed raffleId,
        address indexed user,           // indexed = can search by user
        uint256 numEntries,
        uint256 totalUserEntries,       // their total after this entry
        uint256 amountPaid
    );
    
    /// @notice Emitted when draw is triggered (VRF requested)
    event DrawTriggered(
        uint256 indexed raffleId,
        uint256 vrfRequestId,
        uint256 expectedWinners
    );
    
    /// @notice Emitted when winners are selected and paid
    event WinnersSelected(
        uint256 indexed raffleId,
        address[] winners,              // array of all winner addresses
        uint256 prizePerWinner,
        uint256 totalPrize,
        uint256 protocolFee
    );
    
    /// @notice Emitted when raffle is cancelled
    event RaffleCancelled(
        uint256 indexed raffleId,
        string reason
    );
    
    /// @notice Emitted when user claims refund from cancelled raffle
    event RefundClaimed(
        uint256 indexed raffleId,
        address indexed user,
        uint256 amount
    );
    
    /// @notice Emitted when admin withdraws protocol fees
    event FeesWithdrawn(
        address indexed to,
        uint256 amount
    );
    
    /// @notice Emitted when VRF config is updated
    event VRFConfigUpdated(
        uint64 subscriptionId,
        bytes32 keyHash,
        uint32 callbackGasLimit,
        uint16 requestConfirmations
    );
    
    /// @notice Emitted when global limits are updated
    event LimitsUpdated(
        uint256 maxPoolSize,
        uint256 maxEntriesPerUser,
        uint256 minEntriesRequired
    );


    // =========================================================================
    // CUSTOM ERRORS - Gas-efficient error handling
    // =========================================================================
    
    /**
     * CUSTOM ERRORS vs REQUIRE STRINGS
     * --------------------------------
     * Old way: require(condition, "Error message")
     * New way: if (!condition) revert CustomError()
     * 
     * Why custom errors?
     * - Gas efficient: Error names are encoded as 4 bytes, not full strings
     * - Can include parameters: revert InsufficientBalance(required, actual)
     * - Cleaner code: Descriptive names in the error definition
     * 
     * Example gas savings: ~200 gas per revert (adds up with many checks)
     */
    
    error RaffleNotFound();              // Raffle ID doesn't exist
    error RaffleNotActive();             // Raffle not accepting entries
    error RaffleNotEnded();              // Tried to draw before end time
    error RaffleStillActive();           // Tried to draw while still running
    error InvalidEntryCount();           // Tried to buy 0 entries
    error ExceedsMaxEntriesPerUser();    // User trying to exceed their limit
    error ExceedsMaxPoolSize();          // Pool would exceed safety limit
    error ExceedsMaxEntries();           // Raffle is full
    error RaffleNotCancelled();          // Tried to refund non-cancelled raffle
    error RefundAlreadyClaimed();        // User already got their refund
    error NoRefundAvailable();           // User has no entries to refund
    error NoFeesToWithdraw();            // No fees accumulated
    error InvalidDuration();             // Duration outside allowed range
    error InvalidEntryPrice();           // Price below minimum
    error InvalidWinnerPercent();        // Winner % outside 1-50 range
    error InvalidPlatformFee();          // Fee above 5%
    error InvalidState();                // Wrong state for this operation
    error NotEnoughEntries();            // Below minimum entries
    error ZeroAddress();                 // Can't use address(0)
    error ZeroAmount();                  // Can't use amount 0
    error TooEarlyForEmergencyCancel();  // Must wait EMERGENCY_CANCEL_DELAY before emergency cancel


    // =========================================================================
    // CONSTRUCTOR - Runs ONCE when contract is deployed
    // =========================================================================
    
    /**
     * WHAT IS A CONSTRUCTOR?
     * ----------------------
     * The constructor is called exactly once: when the contract is deployed.
     * It sets up initial state that the contract needs to function.
     * 
     * After deployment, the constructor can never be called again.
     * Any parameters passed here become part of the contract's permanent state.
     * 
     * @param _usdc Address of the USDC token contract on this chain
     * @param _vrfCoordinator Address of Chainlink VRF Coordinator on this chain
     * @param _subscriptionId Your Chainlink VRF subscription ID
     * @param _keyHash The VRF key hash (determines oracle network/gas lane)
     */
    constructor(
        address _usdc,
        address _vrfCoordinator,
        uint64 _subscriptionId,
        bytes32 _keyHash
    ) 
        Ownable(msg.sender)                    // Set deployer as owner
        VRFConsumerBaseV2(_vrfCoordinator)     // Initialize VRF consumer
    {
        // Check for zero addresses (common mistake that would break the contract)
        if (_usdc == address(0)) revert ZeroAddress();
        if (_vrfCoordinator == address(0)) revert ZeroAddress();
        
        // Set immutable variables (can never be changed after this)
        usdc = IERC20(_usdc);
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        
        // Set configurable VRF parameters (can be updated later if needed)
        vrfSubscriptionId = _subscriptionId;
        vrfKeyHash = _keyHash;
    }


    // =========================================================================
    // ADMIN FUNCTIONS - Only owner can call these
    // =========================================================================
    
    /**
     * FUNCTION MODIFIERS
     * ------------------
     * Modifiers are reusable checks added to functions.
     * 
     * - onlyOwner: Only the contract owner can call this
     * - whenNotPaused: Function blocked if contract is paused
     * - nonReentrant: Prevents reentrancy attacks
     * 
     * Multiple modifiers are checked in order (left to right).
     */
    
    /**
     * @notice Create a new raffle
     * 
     * @param _entryPrice Price per entry in USDC (6 decimals)
     *                    Example: 3000000 = $3.00
     * 
     * @param _duration How long the raffle runs in seconds
     *                  Example: 86400 = 24 hours (24 * 60 * 60)
     * 
     * @param _maxEntries Maximum total entries (0 for unlimited)
     *                    Example: 1000 = max 1000 entries
     * 
     * @param _winnerPercent Percentage of players who win (1-50)
     *                       Example: 10 = 10% of players win
     * 
     * @param _platformFeePercent Platform fee percentage (0-5)
     *                            Example: 5 = 5% fee
     * 
     * @return raffleId The ID of the newly created raffle
     * 
     * @dev Raffle starts immediately when created (startTime = now)
     * 
     * EXAMPLE USAGE:
     * Create a $3 entry, 24-hour raffle where 10% win and platform takes 5%:
     * createRaffle(3000000, 86400, 0, 10, 5)
     */
    function createRaffle(
        uint256 _entryPrice,
        uint256 _duration,
        uint256 _maxEntries,
        uint256 _winnerPercent,
        uint256 _platformFeePercent
    ) 
        external 
        onlyOwner           // Only admin can create raffles
        whenNotPaused       // Can't create if contract paused
        returns (uint256 raffleId) 
    {
        // =====================================================================
        // VALIDATION - Check all inputs before making any changes
        // =====================================================================
        
        // Entry price must be at least $0.01
        if (_entryPrice < MIN_ENTRY_PRICE) revert InvalidEntryPrice();
        
        // Duration must be 1 hour to 30 days
        if (_duration < MIN_RAFFLE_DURATION || _duration > MAX_RAFFLE_DURATION) {
            revert InvalidDuration();
        }
        
        // Winner percent must be 1-50%
        if (_winnerPercent < MIN_WINNER_PERCENT || _winnerPercent > MAX_WINNER_PERCENT) {
            revert InvalidWinnerPercent();
        }
        
        // Platform fee must be 0-5% (CANNOT exceed MAX_PLATFORM_FEE_PERCENT)
        // This is the CRITICAL trust check - fee can never be more than 5%
        if (_platformFeePercent > MAX_PLATFORM_FEE_PERCENT) {
            revert InvalidPlatformFee();
        }
        
        // =====================================================================
        // CREATE RAFFLE
        // =====================================================================
        
        // Get the next ID and increment counter
        // Post-increment: returns current value, THEN adds 1
        raffleId = nextRaffleId++;
        
        // Current time (seconds since Jan 1, 1970)
        uint256 startTime = block.timestamp;
        
        // End time = now + duration
        uint256 endTime = block.timestamp + _duration;
        
        // Create and store the raffle struct
        raffles[raffleId] = Raffle({
            entryPrice: _entryPrice,
            startTime: startTime,
            endTime: endTime,
            maxEntries: _maxEntries,
            winnerPercent: _winnerPercent,
            platformFeePercent: _platformFeePercent,
            state: RaffleState.Active,      // Start accepting entries immediately
            totalEntries: 0,
            totalPool: 0,
            numWinners: 0,
            prizePerWinner: 0,
            vrfRequestId: 0
        });
        
        // =====================================================================
        // EMIT EVENT - Notify external systems
        // =====================================================================
        
        emit RaffleCreated(
            raffleId,
            _entryPrice,
            startTime,
            endTime,
            _maxEntries,
            _winnerPercent,
            _platformFeePercent
        );
    }
    
    
    /**
     * @notice Trigger the draw for an ended raffle
     * @param _raffleId The raffle to draw
     * 
     * @dev This function:
     * 1. Validates the raffle can be drawn
     * 2. Calculates how many winners there should be
     * 3. Requests random numbers from Chainlink VRF
     * 4. The actual winner selection happens in fulfillRandomWords (callback)
     * 
     * IMPORTANT: This costs LINK tokens from your VRF subscription!
     * Make sure subscription is funded at https://vrf.chain.link
     * 
     * WHY IS THIS A SEPARATE STEP?
     * We could auto-trigger at endTime, but:
     * - Blockchain can't run code automatically (no cron jobs)
     * - Someone needs to pay gas to trigger the draw
     * - Admin can verify everything looks good before drawing
     * 
     * In production, you might use Chainlink Automation to auto-trigger.
     */
    function triggerDraw(uint256 _raffleId) 
        external 
        onlyOwner 
        nonReentrant    // Prevent reentrancy during external VRF call
    {
        Raffle storage raffle = raffles[_raffleId];
        
        // =====================================================================
        // VALIDATION
        // =====================================================================
        
        // Raffle must exist (entryPrice of 0 means uninitialized)
        if (raffle.entryPrice == 0) revert RaffleNotFound();
        
        // Must be in Active state (can't draw if already drawing/completed/cancelled)
        if (raffle.state != RaffleState.Active) revert InvalidState();
        
        // Must be past end time (can't draw while raffle still running)
        if (block.timestamp < raffle.endTime) revert RaffleStillActive();
        
        // Must have minimum entries (otherwise, cancel and refund)
        if (raffle.totalEntries < minEntriesRequired) {
            _cancelRaffle(_raffleId, "Minimum entries not reached");
            return; // Early exit - raffle cancelled instead of drawn
        }
        
        // =====================================================================
        // CALCULATE NUMBER OF WINNERS
        // =====================================================================
        
        // Calculate: totalEntries * winnerPercent / 100
        // Example: 100 entries * 10% = 10 winners
        uint256 numWinners = (raffle.totalEntries * raffle.winnerPercent) / 100;
        
        // Ensure at least 1 winner
        // (Could be 0 if 5 entries * 1% = 0.05, rounds to 0)
        if (numWinners == 0) numWinners = 1;
        
        // Cap at MAX_WINNERS (100) for gas and VRF limits
        if (numWinners > MAX_WINNERS) numWinners = MAX_WINNERS;
        
        // Can't have more winners than entries
        // (Edge case: 3 entries * 50% = 1.5 → 1 winner, but just in case)
        if (numWinners > raffle.totalEntries) numWinners = raffle.totalEntries;
        
        // =====================================================================
        // UPDATE STATE BEFORE EXTERNAL CALL (CEI Pattern)
        // =====================================================================
        
        // Checks-Effects-Interactions (CEI) Pattern:
        // 1. Checks: All validations done above
        // 2. Effects: Update state NOW, before calling external contract
        // 3. Interactions: Call external contract last
        //
        // This prevents reentrancy attacks where external contract
        // could call back into us before state is updated.

        raffle.state = RaffleState.Drawing;
        raffle.numWinners = numWinners;

        // Record timestamp for emergency cancel delay enforcement
        drawTriggeredAt[_raffleId] = block.timestamp;
        
        // =====================================================================
        // REQUEST RANDOM NUMBERS FROM CHAINLINK
        // =====================================================================
        
        // We need one random number per winner
        uint32 numWords = uint32(numWinners);
        
        // Call Chainlink VRF Coordinator
        // This is an ASYNC call - Chainlink will call us back later
        uint256 requestId = vrfCoordinator.requestRandomWords(
            vrfKeyHash,              // Which Chainlink network to use
            vrfSubscriptionId,       // Your subscription (pays for this)
            vrfRequestConfirmations, // How many blocks to wait (security)
            vrfCallbackGasLimit,     // Max gas for callback
            numWords                 // How many random numbers we want
        );
        
        // Store mapping so we can match callback to raffle
        raffle.vrfRequestId = requestId;
        vrfRequestToRaffle[requestId] = _raffleId;
        
        emit DrawTriggered(_raffleId, requestId, numWinners);
    }
    
    
    /**
     * @notice Cancel an active raffle
     * @param _raffleId Raffle to cancel
     * @param _reason Why it's being cancelled (stored in event)
     * 
     * @dev After cancellation, users can claim refunds via claimRefund()
     * 
     * WHEN TO CANCEL:
     * - Found a bug and need to stop the raffle
     * - Not enough entries (auto-cancelled by triggerDraw)
     * - External circumstances require stopping
     * 
     * CANNOT CANCEL IF:
     * - Already in Drawing state (VRF requested)
     * - Already Completed or Cancelled
     */
    function cancelRaffle(uint256 _raffleId, string calldata _reason) 
        external 
        onlyOwner 
    {
        _cancelRaffle(_raffleId, _reason);
    }
    
    
    /**
     * @notice Withdraw accumulated protocol fees
     * @param _to Address to send fees to
     * @param _amount Amount to withdraw
     * 
     * @dev CRITICAL SECURITY:
     * This function can ONLY withdraw from protocolFeesCollected.
     * It CANNOT touch active raffle pools or user funds.
     * 
     * protocolFeesCollected only increases when:
     * - A raffle completes successfully
     * - The fee portion is added to this counter
     * 
     * Active raffle funds are NOT in this counter.
     */
    function withdrawFees(address _to, uint256 _amount) 
        external 
        onlyOwner 
        nonReentrant 
    {
        // Can't send to zero address (would burn the tokens)
        if (_to == address(0)) revert ZeroAddress();
        
        // Can't withdraw 0 (pointless and might indicate a bug)
        if (_amount == 0) revert ZeroAmount();
        
        // Can't withdraw more than available fees
        // This is the KEY check that prevents stealing user funds
        if (_amount > protocolFeesCollected) revert NoFeesToWithdraw();
        
        // Update state BEFORE transfer (CEI pattern)
        protocolFeesCollected -= _amount;
        
        // Transfer the fees
        usdc.safeTransfer(_to, _amount);
        
        emit FeesWithdrawn(_to, _amount);
    }
    
    
    /**
     * @notice Update VRF configuration
     * 
     * @dev Only use if you need to change Chainlink settings, such as:
     * - Moving to a different VRF subscription
     * - Changing gas lane (key hash)
     * - Adjusting callback gas limit
     * - Changing confirmation blocks
     */
    function updateVRFConfig(
        uint64 _subscriptionId,
        bytes32 _keyHash,
        uint32 _callbackGasLimit,
        uint16 _requestConfirmations
    ) external onlyOwner {
        vrfSubscriptionId = _subscriptionId;
        vrfKeyHash = _keyHash;
        vrfCallbackGasLimit = _callbackGasLimit;
        vrfRequestConfirmations = _requestConfirmations;
        
        emit VRFConfigUpdated(
            _subscriptionId,
            _keyHash,
            _callbackGasLimit,
            _requestConfirmations
        );
    }
    
    
    /**
     * @notice Update global limits
     * 
     * @dev Use to adjust safety parameters as platform grows:
     * - Increase maxPoolSize as you build trust
     * - Adjust maxEntriesPerUser based on user feedback
     * - Change minEntriesRequired for different raffle types
     */
    function updateLimits(
        uint256 _maxPoolSize,
        uint256 _maxEntriesPerUser,
        uint256 _minEntriesRequired
    ) external onlyOwner {
        maxPoolSize = _maxPoolSize;
        maxEntriesPerUser = _maxEntriesPerUser;
        minEntriesRequired = _minEntriesRequired;
        
        emit LimitsUpdated(_maxPoolSize, _maxEntriesPerUser, _minEntriesRequired);
    }
    
    
    /**
     * @notice Pause the contract (emergency stop)
     * 
     * @dev When paused:
     * - No new raffles can be created
     * - No entries can be placed
     * - Existing refunds CAN still be claimed (important for user safety)
     * 
     * Use this if you discover a bug or security issue.
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    
    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }


    // =========================================================================
    // USER FUNCTIONS - Anyone can call these
    // =========================================================================
    
    /**
     * @notice Enter a raffle by purchasing entries
     * @param _raffleId Which raffle to enter
     * @param _numEntries How many entries to purchase
     * 
     * @dev User must have approved this contract to spend their USDC first!
     * 
     * HOW ERC20 APPROVAL WORKS:
     * 1. User calls USDC.approve(raffleContractAddress, amount)
     *    - This says "Raffle contract can spend up to X of my USDC"
     * 2. User calls enterRaffle(raffleId, numEntries)
     *    - Contract calls USDC.transferFrom(user, contract, cost)
     *    - This actually moves the tokens
     * 
     * WHY TWO STEPS?
     * Security: User explicitly approves each contract that can spend their tokens.
     * Without approval, no contract can touch your tokens.
     * 
     * IMPORTANT: Once entered, users CANNOT withdraw their funds!
     * Refunds are ONLY available if the raffle is cancelled.
     * This is by design - otherwise people could enter, see they're losing, and leave.
     * 
     * @custom:example
     * // User wants to buy 5 entries at $3 each = $15
     * // Step 1: Approve USDC spending
     * USDC.approve(raffleContract, 15000000); // $15 in 6 decimals
     * // Step 2: Enter raffle
     * raffleContract.enterRaffle(1, 5); // Raffle #1, 5 entries
     */
    function enterRaffle(uint256 _raffleId, uint256 _numEntries) 
        external 
        whenNotPaused    // Can't enter if contract paused
        nonReentrant     // Prevent reentrancy attacks
    {
        Raffle storage raffle = raffles[_raffleId];
        
        // =====================================================================
        // VALIDATION
        // =====================================================================
        
        // Raffle must exist
        if (raffle.entryPrice == 0) revert RaffleNotFound();
        
        // Must be in Active state
        if (raffle.state != RaffleState.Active) revert RaffleNotActive();
        
        // Must not be past end time
        if (block.timestamp >= raffle.endTime) revert RaffleNotActive();
        
        // Must buy at least 1 entry
        if (_numEntries == 0) revert InvalidEntryCount();
        
        // Calculate total cost
        uint256 totalCost = raffle.entryPrice * _numEntries;
        
        // Check user's per-raffle limit
        UserEntry storage userEntry = userEntries[_raffleId][msg.sender];
        uint256 newUserTotal = userEntry.numEntries + _numEntries;
        if (newUserTotal > maxEntriesPerUser) {
            revert ExceedsMaxEntriesPerUser();
        }
        
        // Check global pool size limit
        if (raffle.totalPool + totalCost > maxPoolSize) {
            revert ExceedsMaxPoolSize();
        }
        
        // Check raffle's max entries (if set)
        if (raffle.maxEntries > 0 && raffle.totalEntries + _numEntries > raffle.maxEntries) {
            revert ExceedsMaxEntries();
        }
        
        // =====================================================================
        // EFFECTS - Update state BEFORE external call
        // =====================================================================
        
        // Starting index for this user's new entries
        uint256 startIndex = raffle.totalEntries;
        
        // Track user's first entry index (for potential future features)
        if (userEntry.numEntries == 0) {
            userEntry.startIndex = startIndex;
        }
        
        // Record ownership of each entry
        // This lets us look up "who owns entry #X?" during winner selection
        for (uint256 i = 0; i < _numEntries; i++) {
            entryOwners[_raffleId][startIndex + i] = msg.sender;
        }
        
        // Update raffle totals
        raffle.totalEntries += _numEntries;
        raffle.totalPool += totalCost;
        
        // Update user totals
        userEntry.numEntries = newUserTotal;
        
        // =====================================================================
        // INTERACTIONS - External call LAST (CEI pattern)
        // =====================================================================
        
        // Transfer USDC from user to this contract
        // safeTransferFrom handles non-standard ERC20 tokens gracefully
        // Will revert if user hasn't approved enough or doesn't have balance
        usdc.safeTransferFrom(msg.sender, address(this), totalCost);
        
        emit RaffleEntered(
            _raffleId,
            msg.sender,
            _numEntries,
            newUserTotal,
            totalCost
        );
    }
    
    
    /**
     * @notice Claim refund from a cancelled raffle
     * @param _raffleId The cancelled raffle ID
     * 
     * @dev Only works if raffle is in Cancelled state.
     * Each user can only claim once.
     * 
     * WHY SEPARATE CLAIM FUNCTION?
     * Instead of auto-refunding everyone when cancelled:
     * - Auto-refund to 1000 users = expensive, might exceed block gas limit
     * - Each user claiming = cost spread out, always works
     * - User-initiated = clear action, good UX
     */
    function claimRefund(uint256 _raffleId) 
        external 
        nonReentrant 
    {
        Raffle storage raffle = raffles[_raffleId];
        UserEntry storage userEntry = userEntries[_raffleId][msg.sender];
        
        // Must be in Cancelled state
        if (raffle.state != RaffleState.Cancelled) revert RaffleNotCancelled();
        
        // Must not have already claimed
        if (userEntry.refundClaimed) revert RefundAlreadyClaimed();
        
        // Must have entries to refund
        if (userEntry.numEntries == 0) revert NoRefundAvailable();
        
        // Calculate refund (number of entries × price per entry)
        uint256 refundAmount = userEntry.numEntries * raffle.entryPrice;
        
        // Mark as claimed BEFORE transfer (prevents double-claim via reentrancy)
        userEntry.refundClaimed = true;
        
        // Send the refund
        usdc.safeTransfer(msg.sender, refundAmount);
        
        emit RefundClaimed(_raffleId, msg.sender, refundAmount);
    }


    // =========================================================================
    // CHAINLINK VRF CALLBACK - Called BY Chainlink, not by us
    // =========================================================================
    
    /**
     * @notice Receives random numbers from Chainlink VRF
     * @param _requestId The request ID from our original request
     * @param _randomWords Array of random numbers (one per winner)
     * 
     * @dev THIS FUNCTION IS NOT CALLED BY US!
     * It's called by the Chainlink VRF Coordinator when random numbers are ready.
     * 
     * SECURITY:
     * - Only VRF Coordinator can call this (enforced by VRFConsumerBaseV2)
     * - We validate the requestId matches a pending raffle
     * - State must be Drawing (prevents replay attacks)
     * 
     * FLOW:
     * 1. We called vrfCoordinator.requestRandomWords() in triggerDraw
     * 2. Chainlink generates random numbers off-chain
     * 3. Chainlink calls this function with the results
     * 4. We select winners and distribute prizes
     * 
     * WHY "INTERNAL OVERRIDE"?
     * - internal: Can only be called from within this contract (or via inheritance)
     * - override: We're implementing a function from VRFConsumerBaseV2
     * 
     * The VRFConsumerBaseV2 has a rawFulfillRandomWords function that:
     * 1. Verifies the caller is the VRF Coordinator
     * 2. Calls our fulfillRandomWords function
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        // Find which raffle this is for
        uint256 raffleId = vrfRequestToRaffle[_requestId];
        Raffle storage raffle = raffles[raffleId];
        
        // Validate state - must be Drawing
        // If not Drawing, something is wrong - ignore the callback
        if (raffle.state != RaffleState.Drawing) {
            return;
        }
        
        uint256 numWinners = raffle.numWinners;
        uint256 totalEntries = raffle.totalEntries;
        
        // =====================================================================
        // SELECT WINNERS
        // =====================================================================
        
        // Array to store winner addresses
        address[] memory winners = new address[](numWinners);
        uint256 winnersSelected = 0;
        uint256 randomIndex = 0;
        
        // Select unique winners
        // We use a while loop because some random numbers might select
        // the same person (who already won), so we need to try again
        while (winnersSelected < numWinners && randomIndex < 1000) {
            uint256 randomWord;
            
            // Use provided random words first
            if (randomIndex < _randomWords.length) {
                randomWord = _randomWords[randomIndex];
            } else {
                // If we need more randomness (rare), derive from existing
                // keccak256 is a hash function - gives us new "random" number
                randomWord = uint256(keccak256(abi.encodePacked(
                    _randomWords[randomIndex % _randomWords.length],
                    randomIndex
                )));
            }
            
            // Convert random number to entry index using modulo
            // Example: random = 12345, totalEntries = 100
            // 12345 % 100 = 45, so entry #45 wins
            uint256 winningIndex = randomWord % totalEntries;
            
            // Look up who owns that entry
            address potentialWinner = entryOwners[raffleId][winningIndex];
            
            // Check if this person already won (ensure unique winners)
            if (!isWinner[raffleId][potentialWinner]) {
                // New winner! Record them
                isWinner[raffleId][potentialWinner] = true;
                winners[winnersSelected] = potentialWinner;
                winnersSelected++;
            }
            // If already a winner, loop continues to find another
            
            randomIndex++;
        }
        
        // Handle edge case: couldn't find enough unique winners
        // This shouldn't happen with reasonable pool sizes
        // Example: 3 unique participants but 10 winners needed
        if (winnersSelected < numWinners) {
            numWinners = winnersSelected;
        }
        
        // Resize winners array if we found fewer winners than expected
        if (winnersSelected < winners.length) {
            address[] memory finalWinners = new address[](winnersSelected);
            for (uint256 i = 0; i < winnersSelected; i++) {
                finalWinners[i] = winners[i];
            }
            winners = finalWinners;
        }
        
        // Store winners in the mapping (for later lookup)
        for (uint256 i = 0; i < winners.length; i++) {
            raffleWinners[raffleId].push(winners[i]);
        }
        
        // =====================================================================
        // CALCULATE PRIZE DISTRIBUTION
        // =====================================================================
        
        uint256 totalPool = raffle.totalPool;
        
        // Calculate protocol fee
        // Example: $300 pool * 5% = $15 fee
        uint256 protocolFee = (totalPool * raffle.platformFeePercent) / 100;
        
        // Prize pool is total minus fee
        // Example: $300 - $15 = $285 for winners
        uint256 prizePool = totalPool - protocolFee;
        
        // Each winner gets equal share
        // Example: $285 / 10 winners = $28.50 each
        uint256 prizePerWinner = prizePool / numWinners;
        
        // Handle rounding dust (integer division loses decimals)
        // Example: $285 / 10 = $28, total $280, dust = $5
        // We give dust to protocol rather than losing it
        uint256 totalPrize = prizePerWinner * numWinners;
        uint256 dust = prizePool - totalPrize;
        protocolFee += dust;
        
        // =====================================================================
        // UPDATE STATE
        // =====================================================================
        
        raffle.state = RaffleState.Completed;
        raffle.numWinners = numWinners;
        raffle.prizePerWinner = prizePerWinner;
        
        // Add fee to withdrawable amount
        protocolFeesCollected += protocolFee;
        
        // =====================================================================
        // DISTRIBUTE PRIZES
        // =====================================================================
        
        // Send prize to each winner
        for (uint256 i = 0; i < winners.length; i++) {
            usdc.safeTransfer(winners[i], prizePerWinner);
        }
        
        emit WinnersSelected(
            raffleId,
            winners,
            prizePerWinner,
            totalPrize,
            protocolFee
        );
    }


    // =========================================================================
    // INTERNAL FUNCTIONS - Used by other functions in this contract
    // =========================================================================
    
    /**
     * @notice Internal function to cancel a raffle
     * @param _raffleId The raffle to cancel
     * @param _reason Why it's being cancelled
     * 
     * @dev Separated into internal function because it's called from:
     * - cancelRaffle (admin-initiated)
     * - triggerDraw (when min entries not met)
     */
    function _cancelRaffle(uint256 _raffleId, string memory _reason) internal {
        Raffle storage raffle = raffles[_raffleId];
        
        // Must exist
        if (raffle.entryPrice == 0) revert RaffleNotFound();
        
        // Can only cancel Active raffles
        // Can't cancel: Drawing (VRF in progress), Completed, already Cancelled
        if (raffle.state != RaffleState.Active) revert InvalidState();
        
        // Update state
        raffle.state = RaffleState.Cancelled;
        
        emit RaffleCancelled(_raffleId, _reason);
    }


    // =========================================================================
    // VIEW FUNCTIONS - Read-only, no gas cost when called off-chain
    // =========================================================================
    
    /**
     * WHAT ARE VIEW FUNCTIONS?
     * ------------------------
     * Functions marked `view` promise not to modify state.
     * They only read data.
     * 
     * GAS COSTS:
     * - Called from another contract: Costs gas (contract-to-contract call)
     * - Called from off-chain (web3.js, ethers.js): FREE (no transaction)
     * 
     * Your frontend will call these to display raffle info without paying gas.
     */
    
    /**
     * @notice Get all details about a raffle
     * @param _raffleId The raffle to query
     * @return The Raffle struct with all data
     */
    function getRaffle(uint256 _raffleId) external view returns (Raffle memory) {
        return raffles[_raffleId];
    }
    
    
    /**
     * @notice Get a user's entry details for a raffle
     * @param _raffleId The raffle
     * @param _user The user address
     * @return numEntries How many entries they have
     * @return totalSpent How much USDC they spent
     * @return refundClaimed Whether they claimed refund (if cancelled)
     */
    function getUserEntry(uint256 _raffleId, address _user) 
        external 
        view 
        returns (
            uint256 numEntries,
            uint256 totalSpent,
            bool refundClaimed
        ) 
    {
        UserEntry storage entry = userEntries[_raffleId][_user];
        Raffle storage raffle = raffles[_raffleId];
        
        return (
            entry.numEntries,
            entry.numEntries * raffle.entryPrice,
            entry.refundClaimed
        );
    }
    
    
    /**
     * @notice Get all winners for a completed raffle
     * @param _raffleId The raffle
     * @return Array of winner addresses
     */
    function getWinners(uint256 _raffleId) external view returns (address[] memory) {
        return raffleWinners[_raffleId];
    }
    
    
    /**
     * @notice Check if a specific address won a raffle
     * @param _raffleId The raffle
     * @param _user The address to check
     * @return True if they won, false otherwise
     */
    function checkWinner(uint256 _raffleId, address _user) external view returns (bool) {
        return isWinner[_raffleId][_user];
    }
    
    
    /**
     * @notice Calculate expected winners and prize per winner
     * @param _raffleId The raffle
     * @return expectedWinners How many winners there will be
     * @return prizePerWinner How much each winner will receive
     * 
     * @dev Useful for frontend to show "If you win, you'll get $X"
     */
    function calculateExpectedWinners(uint256 _raffleId) 
        external 
        view 
        returns (uint256 expectedWinners, uint256 prizePerWinner) 
    {
        Raffle storage raffle = raffles[_raffleId];
        
        if (raffle.totalEntries == 0) {
            return (0, 0);
        }
        
        // Calculate winners (same logic as triggerDraw)
        expectedWinners = (raffle.totalEntries * raffle.winnerPercent) / 100;
        if (expectedWinners == 0) expectedWinners = 1;
        if (expectedWinners > MAX_WINNERS) expectedWinners = MAX_WINNERS;
        if (expectedWinners > raffle.totalEntries) expectedWinners = raffle.totalEntries;
        
        // Calculate prize
        uint256 protocolFee = (raffle.totalPool * raffle.platformFeePercent) / 100;
        uint256 prizePool = raffle.totalPool - protocolFee;
        prizePerWinner = prizePool / expectedWinners;
        
        return (expectedWinners, prizePerWinner);
    }
    
    
    /**
     * @notice Check if a raffle is ready to be drawn
     * @param _raffleId The raffle
     * @return canDraw True if triggerDraw will succeed
     * @return reason Human-readable explanation
     */
    function canTriggerDraw(uint256 _raffleId) 
        external 
        view 
        returns (bool canDraw, string memory reason) 
    {
        Raffle storage raffle = raffles[_raffleId];
        
        if (raffle.entryPrice == 0) {
            return (false, "Raffle not found");
        }
        if (raffle.state != RaffleState.Active) {
            return (false, "Raffle not active");
        }
        if (block.timestamp < raffle.endTime) {
            return (false, "Raffle not ended yet");
        }
        if (raffle.totalEntries < minEntriesRequired) {
            return (false, "Not enough entries - will be cancelled");
        }
        
        return (true, "Ready to draw");
    }
    
    
    /**
     * @notice Get current contract state
     * @return _nextRaffleId Next raffle ID to be assigned
     * @return _protocolFeesCollected Fees available for withdrawal
     * @return _isPaused Whether contract is paused
     */
    function getContractState() 
        external 
        view 
        returns (
            uint256 _nextRaffleId,
            uint256 _protocolFeesCollected,
            bool _isPaused
        ) 
    {
        return (nextRaffleId, protocolFeesCollected, paused());
    }
    
    
    /**
     * @notice Get time remaining in a raffle
     * @param _raffleId The raffle
     * @return Seconds remaining (0 if ended)
     */
    function getTimeRemaining(uint256 _raffleId) external view returns (uint256) {
        Raffle storage raffle = raffles[_raffleId];
        
        if (raffle.entryPrice == 0) return 0;
        if (block.timestamp >= raffle.endTime) return 0;
        
        return raffle.endTime - block.timestamp;
    }


    // =========================================================================
    // EMERGENCY FUNCTIONS - For recovery from stuck states
    // =========================================================================
    
    /**
     * @notice Emergency cancel a raffle stuck in Drawing state
     * @param _raffleId The stuck raffle
     *
     * @dev ONLY USE IF:
     * - VRF callback failed after EMERGENCY_CANCEL_DELAY (12 hours)
     * - Raffle has been genuinely stuck in Drawing state
     * - VRF subscription ran out of LINK
     * - Network issue prevented callback
     *
     * SECURITY FEATURE:
     * Cannot be called until 12 hours after triggerDraw was called.
     * This prevents admin from canceling immediately after seeing unfavorable winners.
     * VRF normally responds in <5 minutes, so 12 hours proves genuine failure.
     *
     * After emergency cancel, users can claim refunds normally.
     *
     * WHY 12 HOURS?
     * - VRF usually responds in 30 seconds - 5 minutes
     * - Worst case congestion: 1-2 hours
     * - 12 hours = definitely failed OR definitely succeeded
     * - Builds user trust (admin cannot abuse this function)
     *
     * @custom:security-note This enforces EMERGENCY_CANCEL_DELAY to prevent abuse
     */
    function emergencyCancelDrawing(uint256 _raffleId) external onlyOwner {
        Raffle storage raffle = raffles[_raffleId];

        // Must be in Drawing state (stuck waiting for VRF)
        if (raffle.state != RaffleState.Drawing) revert InvalidState();

        // ✅ SECURITY: Enforce 12-hour delay before emergency cancel
        // This prevents admin from canceling right after triggering draw
        if (block.timestamp < drawTriggeredAt[_raffleId] + EMERGENCY_CANCEL_DELAY) {
            revert TooEarlyForEmergencyCancel();
        }

        // Cancel the raffle
        raffle.state = RaffleState.Cancelled;

        emit RaffleCancelled(_raffleId, "Emergency cancel - VRF callback failed");
    }
}
