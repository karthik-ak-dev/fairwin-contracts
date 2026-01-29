# FairWin Raffle - Smart Contract

A provably fair, multi-winner raffle system on Polygon using Chainlink VRF.

## Features

- **Multi-winner**: Configurable 1-50% of participants win
- **Provably fair**: Chainlink VRF for verifiable randomness
- **Capped fees**: Maximum 5% platform fee (hardcoded)
- **Non-custodial**: Funds held by smart contract, not a person
- **Fully documented**: Beginner-friendly code comments

## Quick Start

### 1. Install Dependencies

```bash
npm install
```

### 2. Setup Environment

```bash
cp .env.example .env
# Edit .env with your values
```

### 3. Compile

```bash
npx hardhat compile
```

### 4. Test

```bash
npx hardhat test
```

### 5. Deploy

```bash
# Local
npx hardhat run scripts/deploy.ts

# Testnet (Amoy)
npx hardhat run scripts/deploy.ts --network amoy

# Mainnet (Polygon)
npx hardhat run scripts/deploy.ts --network polygon
```

## Project Structure

```
├── contracts/
│   ├── FairWinRaffle.sol       # Main raffle contract
│   └── mocks/
│       ├── MockVRFCoordinator.sol  # For testing
│       └── MockERC20.sol           # Mock USDC
├── test/
│   └── FairWinRaffle.test.js   # Test suite
├── scripts/
│   └── deploy.ts               # Deployment script
├── SECURITY_AUDIT.md           # Security analysis
└── hardhat.config.ts           # Hardhat configuration
```

## Contract Configuration

### Hardcoded (Cannot Change)

| Parameter | Value | Purpose |
|-----------|-------|---------|
| MAX_PLATFORM_FEE | 5% | Users trust fee can't exceed this |
| MAX_WINNERS | 100 | Gas limit safety |
| MAX_WINNER_PERCENT | 50% | At most half can win |
| MIN_DURATION | 1 hour | Minimum raffle length |
| MAX_DURATION | 30 days | Maximum raffle length |

### Per-Raffle (Set at Creation)

| Parameter | Range | Example |
|-----------|-------|---------|
| Entry Price | $0.01+ | $3.00 |
| Duration | 1hr - 30 days | 24 hours |
| Max Entries | 0 (unlimited) - any | 1000 |
| Winner % | 1-50% | 10% |
| Platform Fee | 0-5% | 5% |

## Example Usage

### Create a Raffle

```javascript
// $3 entry, 24 hours, unlimited entries, 10% win, 5% fee
await raffle.createRaffle(
  3000000,   // $3.00 in USDC (6 decimals)
  86400,     // 24 hours in seconds
  0,         // No entry limit
  10,        // 10% of players win
  5          // 5% platform fee
);
```

### Enter a Raffle

```javascript
// First, approve USDC spending
await usdc.approve(raffleAddress, 3000000);

// Then enter with 1 entry
await raffle.enterRaffle(1, 1);
```

### Trigger Draw

```javascript
// After raffle ends
await raffle.triggerDraw(1);
// Chainlink VRF will call back with winners
```

## Chainlink VRF Setup

1. Go to [vrf.chain.link](https://vrf.chain.link)
2. Create a subscription
3. Fund it with LINK tokens
4. Add your deployed contract as a consumer
5. Update `VRF_SUBSCRIPTION_ID` in your `.env`

## Security

See [SECURITY_AUDIT.md](./SECURITY_AUDIT.md) for full security analysis.

### Key Guarantees

- ✅ Admin cannot take more than 5% fee
- ✅ Admin cannot steal user funds
- ✅ Users cannot withdraw after entering (prevents gaming)
- ✅ Refunds only available if raffle cancelled
- ✅ Chainlink VRF ensures fair randomness

## Networks

| Network | Chain ID | USDC | VRF Coordinator |
|---------|----------|------|-----------------|
| Polygon | 137 | 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359 | 0xAE975071Be8F8eE67addBC1A82488F1C24858067 |
| Amoy (Testnet) | 80002 | 0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582 | 0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed |

## License

MIT
