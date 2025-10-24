# AuraFi Oracle

The AuraFi Oracle is an off-chain service that computes creator aura scores from Farcaster social metrics and updates the on-chain AuraOracle contract. It acts as a trusted data provider, fetching real-time creator metrics, computing weighted aura scores, and storing verifiable evidence on IPFS.

## Overview

The oracle system consists of three main components:

1. **oracle.js** - Main oracle script that fetches metrics, computes aura, and updates the contract
2. **test-oracle.js** - Testing script to verify data was written correctly
3. **AuraOracle.sol** - On-chain smart contract that stores aura scores

## Architecture

```
┌─────────────────┐
│   Farcaster     │
│   (Neynar API)  │
└────────┬────────┘
         │
         │ Fetch Metrics
         ▼
┌─────────────────┐      Pin Evidence      ┌─────────────┐
│   oracle.js     │─────────────────────────▶│    IPFS     │
│                 │                          │  (Pinata)   │
└────────┬────────┘                          └─────────────┘
         │
         │ pushAura(vault, aura, ipfsHash)
         ▼
┌─────────────────┐
│  AuraOracle.sol │
│   (On-chain)    │
└────────┬────────┘
         │
         │ getAura(vault)
         │ getIpfsHash(vault)
         ▼
┌─────────────────┐
│ test-oracle.js  │
│   (Verify)      │
└─────────────────┘
```

## Features

- **Real-time Metrics**: Fetches live creator data from Farcaster via Neynar API
- **Weighted Scoring**: Computes aura using configurable weights for different metrics
- **IPFS Evidence**: Stores computation details and raw metrics on IPFS for transparency
- **Cooldown Protection**: Enforces 6-hour cooldown between updates per vault
- **Mock Mode**: Test without API keys using hardcoded data
- **Dry Run**: Compute aura without sending transactions

## Installation

```bash
# Install dependencies
npm install

# Or using yarn
yarn install
```

### Dependencies

- `ethers` - Ethereum library for contract interaction
- `axios` - HTTP client for API calls
- `dotenv` - Environment variable management

## Configuration

Create a `.env.local` file in the `oracle/` directory:

```env
# Network Configuration
RPC_URL=https://rpc.ankr.com/celo_sepolia

# Oracle Contract
ORACLE_CONTRACT_ADDRESS=0xa585e63cfAeFc513198d70FbA741B22d8116C2d0

# Oracle Wallet (must be authorized in contract)
ORACLE_PRIVATE_KEY=your_private_key_here

# Farcaster API (Neynar)
NEYNAR_API_KEY=your_neynar_api_key_here

# IPFS Pinning (Pinata)
PINATA_JWT=your_pinata_jwt_token_here
PINATA_GATEWAY=https://your-gateway.mypinata.cloud
```

### Getting API Keys

**Neynar API (Farcaster Data):**
1. Sign up at [neynar.com](https://neynar.com)
2. Create an API key in the dashboard
3. Free tier includes basic user data

**Pinata (IPFS Pinning):**
1. Sign up at [pinata.cloud](https://pinata.cloud)
2. Generate a JWT token in API Keys section
3. Note your gateway URL

## Usage

### Push Aura Data (Write)

Update aura score for a creator vault:

```bash
node oracle.js --vault <vault-address> --fid <farcaster-id> [options]
```

**Required Arguments:**
- `--vault <address>` - Vault contract address to update
- `--fid <id>` - Creator's Farcaster ID

**Optional Arguments:**
- `--mock` - Use mock data (no API keys needed)
- `--dry-run` - Compute aura but don't send transaction
- `--help` - Show help message

**Examples:**

```bash
# Update with live Farcaster data
node oracle.js --vault 0x1234... --fid 1398844

# Test with mock data
node oracle.js --vault 0x1234... --fid 12345 --mock

# Dry run (compute only, no transaction)
node oracle.js --vault 0x1234... --fid 12345 --dry-run
```

### Fetch Aura Data (Read)

Query aura data for any vault:

```bash
# Run all tests + fetch default vault
node test-oracle.js

# Query specific vault address
node test-oracle.js <vault-address>
```

**Examples:**

```bash
# Query specific vault
node test-oracle.js 0x0000000000000000000000000000000000000003

# Run tests only (uses default test address)
node test-oracle.js
```

## Aura Computation

The aura score (0-200 range) is computed using weighted metrics:

### Metrics & Weights

| Metric | Weight | Description |
|--------|--------|-------------|
| Followers | 35% | Total follower count (log-normalized) |
| Follower Growth | 25% | Recent follower delta (log-normalized) |
| Avg Likes | 30% | Average likes per post (log-normalized) |
| Verification | 10% | Farcaster verification badge bonus |

### Formula

```
aura = (0.35 × norm(followers)) + 
       (0.25 × norm(followerDelta)) + 
       (0.30 × norm(avgLikes)) + 
       (0.10 × verification_bonus) - 
       spam_penalty

where:
- norm() = log-based normalization to 0-200 range
- verification_bonus = 20 if verified, 0 otherwise
- spam_penalty = 20 if high followers but low engagement
```

### Normalization Parameters

```javascript
followers:      min=10,    max=100,000
followerDelta:  min=1,     max=1,000
avgLikes:       min=1,     max=1,000
```

### Example Scores

| Profile | Followers | Growth | Avg Likes | Verified | Aura |
|---------|-----------|--------|-----------|----------|------|
| Small Creator | 50 | 5 | 2 | No | 29 |
| Mid Creator | 5,000 | 150 | 45 | Yes | 136 |
| Large Creator | 50,000 | 500 | 200 | Yes | 175 |
| Spam Account | 100,000 | 0 | 2 | No | 56 |

## Contract Functions

### Write (Oracle Only)

```solidity
function pushAura(
    address vault,
    uint256 aura,
    string calldata ipfsHash
) external onlyOracle
```

Pushes new aura value with IPFS evidence. Enforces 6-hour cooldown.

### Read (Public)

```solidity
function getAura(address vault) external view returns (uint256)
```
Returns current aura score for a vault.

```solidity
function getIpfsHash(address vault) external view returns (string memory)
```
Returns IPFS hash containing metrics evidence.

```solidity
function getLastUpdateTimestamp(address vault) external view returns (uint256)
```
Returns timestamp of last update.

## IPFS Data Structure

Each aura update stores the following data on IPFS:

```json
{
  "fid": "1398844",
  "followerCount": 1,
  "followerDelta": 0,
  "avgLikes": 50,
  "isVerified": false,
  "timestamp": 1761341280000,
  "username": "kzark",
  "displayName": "Kzark",
  "neynarScore": 0.5,
  "aura": 33,
  "computation": {
    "weights": {
      "followers": 0.35,
      "followerDelta": 0.25,
      "avgLikes": 0.30,
      "verification": 0.10
    },
    "normParams": {
      "followers": { "min": 10, "max": 100000, "scale": 200 },
      "followerDelta": { "min": -100, "max": 1000, "scale": 200 },
      "avgLikes": { "min": 1, "max": 1000, "scale": 200 }
    },
    "version": "1.0.0"
  }
}
```

## Security

### Oracle Authorization

Only the authorized oracle address can call `pushAura()`. The oracle address is set during contract deployment and can be updated by the contract owner.

### Cooldown Period

A 6-hour cooldown is enforced between updates for each vault to prevent spam and manipulation.

### Private Key Security

- Never commit `.env.local` to version control
- Use a dedicated wallet for oracle operations
- Rotate keys periodically
- Monitor oracle wallet balance

## Error Handling

### Common Errors

**"ORACLE_CONTRACT_ADDRESS environment variable not set"**
- Solution: Add `ORACLE_CONTRACT_ADDRESS` to `.env.local`

**"AuraOracle ABI not found. Run `forge build` first."**
- Solution: Run `forge build` in project root to compile contracts

**"execution reverted (unknown custom error)"**
- Cause: Cooldown period not elapsed (6 hours)
- Solution: Wait for cooldown or use a different vault

**"network does not support ENS"**
- Cause: Invalid vault address format
- Solution: Use valid Ethereum address (0x...)

**"Unauthorized"**
- Cause: Oracle wallet not authorized in contract
- Solution: Verify oracle address matches contract's `oracleAddress`

## Testing

### Run All Tests

```bash
node test-oracle.js
```

Tests include:
1. ✅ Clamp function
2. ✅ Normalize function
3. ✅ Fetch metrics (mock mode)
4. ✅ Compute aura
5. ✅ Different metric scenarios
6. ✅ Fetch data from contract

### Integration Test

Complete workflow test:

```bash
# Step 1: Push data
node oracle.js --vault 0x0000000000000000000000000000000000000003 --fid 1398844

# Step 2: Verify data
node test-oracle.js 0x0000000000000000000000000000000000000003
```

Expected output:
```json
{
  "vaultAddress": "0x0000000000000000000000000000000000000003",
  "aura": "33",
  "ipfsHash": "QmZLesTUK9xg52mM2tJTkhKi8xRgdTbn21CDmPPuZXDUMv",
  "lastUpdate": "1761341280",
  "lastUpdateDate": "2025-10-24T21:28:00.000Z"
}
```

## Monitoring

### Transaction Logs

Each oracle update logs:
- Transaction hash
- Block number
- Gas used
- Vault address
- Aura score
- IPFS hash

### Event Monitoring

Monitor the `AuraUpdated` event:

```solidity
event AuraUpdated(
    address indexed vault,
    uint256 aura,
    string ipfsHash,
    uint256 timestamp
);
```

## Production Deployment

### Checklist

- [ ] Set production RPC URL
- [ ] Configure production oracle contract address
- [ ] Secure oracle private key
- [ ] Set up Neynar API key
- [ ] Configure Pinata JWT and gateway
- [ ] Test with dry-run mode first
- [ ] Monitor gas prices
- [ ] Set up error alerting
- [ ] Schedule regular updates (cron job)

### Automation

Example cron job to update vaults every 6 hours:

```bash
# crontab -e
0 */6 * * * cd /path/to/oracle && node oracle.js --vault 0x... --fid 12345 >> logs/oracle.log 2>&1
```

## Troubleshooting

### Debug Mode

Enable verbose logging:

```bash
# Add to oracle.js
console.log('Debug:', variable);
```

### Network Issues

If RPC fails, try alternative endpoints:
- Celo Alfajores: `https://alfajores-forno.celo-testnet.org`
- Celo Mainnet: `https://forno.celo.org`
- Ankr: `https://rpc.ankr.com/celo_sepolia`

### Gas Estimation

Typical gas usage:
- First update: ~140,000 gas
- Subsequent updates: ~120,000 gas

## Contributing

When modifying the oracle:

1. Update weights in `WEIGHTS` constant
2. Adjust normalization in `NORM_PARAMS`
3. Test with `--dry-run` first
4. Update IPFS data structure version
5. Document changes in CHANGELOG.md

## License

MIT License - See LICENSE file for details

## Support

For issues or questions:
- GitHub Issues: [Create an issue](https://github.com/your-repo/issues)
- Documentation: See `README-TESTING.md` for detailed testing guide
- Contract: See `../contracts/AuraOracle.sol` for contract details

## Version

Current Version: 1.0.0

Last Updated: October 24, 2025
