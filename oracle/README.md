# AuraFi Oracle

Oracle script for computing creator aura scores from Farcaster metrics and updating vault contracts.

## Overview

The oracle fetches Farcaster activity metrics (followers, engagement, verification status), computes a normalized aura score (0-200), stores the evidence on IPFS, and updates the vault contract on-chain.

## Installation

### Prerequisites

- Node.js v16 or higher
- npm or yarn package manager
- Foundry (for contract compilation)

### Setup Steps

1. **Navigate to oracle directory:**
   ```bash
   cd oracle
   ```

2. **Install dependencies:**
   ```bash
   npm install
   ```

3. **Configure environment variables:**
   
   Copy the example environment file:
   ```bash
   cp .env.example .env.local
   ```

4. **Get your API keys:**

   **Neynar API (Free Tier):**
   - Visit [Neynar Dashboard](https://neynar.com/)
   - Sign up for a free account
   - Create an API key (free tier includes 1000 requests/day)
   - Copy your API key to `.env.local`

   **Pinata (Optional for IPFS):**
   - Visit [Pinata](https://pinata.cloud/)
   - Sign up for a free account (1GB free storage)
   - Generate API keys from Settings → API Keys
   - Copy both API key and secret to `.env.local`

5. **Set up oracle wallet:**
   
   Generate a new wallet for the oracle (or use existing):
   ```bash
   # Using cast (from Foundry)
   cast wallet new
   ```
   
   Copy the private key to `.env.local` as `ORACLE_PRIVATE_KEY`

6. **Compile contracts:**
   
   Return to project root and build contracts:
   ```bash
   cd ..
   forge build
   ```

## Configuration

Edit `oracle/.env.local` with your credentials:

```bash
# Required for live Farcaster data (FREE TIER)
NEYNAR_API_KEY=your_neynar_api_key_here

# Optional: IPFS pinning (FREE TIER available)
PINATA_API_KEY=your_pinata_api_key_here
PINATA_SECRET_KEY=your_pinata_secret_key_here

# Required for on-chain updates
ORACLE_PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000000

# Optional: Custom RPC endpoint (defaults to Celo Alfajores)
RPC_URL=https://alfajores-forno.celo-testnet.org
```

### Environment Variables Explained

| Variable | Required | Description | Free Tier? |
|----------|----------|-------------|------------|
| `NEYNAR_API_KEY` | Yes (for live data) | Neynar API key for Farcaster data | ✅ Yes (1000 req/day) |
| `PINATA_API_KEY` | Optional | Pinata API key for IPFS pinning | ✅ Yes (1GB storage) |
| `PINATA_SECRET_KEY` | Optional | Pinata secret key | ✅ Yes |
| `ORACLE_PRIVATE_KEY` | Yes (for updates) | Private key of authorized oracle wallet | N/A |
| `RPC_URL` | Optional | Blockchain RPC endpoint | ✅ Yes (public RPCs) |

**Note:** If IPFS credentials are not set, the oracle will generate mock IPFS hashes for testing.

## Usage

### Quick Start

1. **Test with mock data (no API keys needed):**
   ```bash
   node oracle.js --vault 0x123... --fid 12345 --mock --dry-run
   ```

2. **Test with real Farcaster data (requires Neynar API key):**
   ```bash
   node oracle.js --vault 0x123... --fid 1398844 --dry-run
   ```

3. **Full execution (updates vault on-chain):**
   ```bash
   node oracle.js --vault 0x123... --fid 12345
   ```

### Command Line Options

```bash
node oracle.js --vault <address> --fid <farcaster-id> [options]
```

| Option | Description | Example |
|--------|-------------|---------|
| `--vault <address>` | **Required.** Vault contract address | `--vault 0x1234...` |
| `--fid <id>` | **Required.** Creator's Farcaster ID | `--fid 12345` |
| `--mock` | Use hardcoded test data (no API calls) | `--mock` |
| `--dry-run` | Compute aura but don't send transaction | `--dry-run` |
| `--help` | Show help message | `--help` |

### Usage Modes

#### 1. Mock Mode (Development)

Perfect for testing without any API keys:

```bash
node oracle.js --vault 0x1234567890123456789012345678901234567890 --fid 12345 --mock --dry-run
```

**Output:**
```
🌟 AuraFi Oracle
================
Vault: 0x1234567890123456789012345678901234567890
Creator FID: 12345
Mode: Mock
Dry Run: Yes

📡 Fetching Farcaster metrics...
🧪 Mock mode: Using hardcoded metrics
✅ Metrics fetched for @12345

📊 Aura Computation:
  Followers: 5000 → 134.95 (weight: 0.35)
  Follower Δ: 150 → 145.07 (weight: 0.25)
  Avg Likes: 45 → 110.21 (weight: 0.3)
  Verified: true → +20.00
  Spam Penalty: -0
  Raw Aura: 136.56
  Final Aura: 136 (clamped to [0, 200])
```

#### 2. Dry Run Mode (Testing with Real Data)

Fetch real Farcaster data but don't send transactions:

```bash
# Set your API key
export NEYNAR_API_KEY="your_key_here"

# Run dry-run
node oracle.js --vault 0x1234567890123456789012345678901234567890 --fid 1398844 --dry-run
```

This mode:
- ✅ Fetches real Farcaster metrics
- ✅ Computes actual aura score
- ✅ Attempts IPFS pinning (if configured)
- ❌ Does NOT send blockchain transaction

#### 3. Production Mode (Full Execution)

Updates the vault contract on-chain:

```bash
# Ensure all environment variables are set
export NEYNAR_API_KEY="your_neynar_key"
export PINATA_API_KEY="your_pinata_key"
export PINATA_SECRET_KEY="your_pinata_secret"
export ORACLE_PRIVATE_KEY="0x..."
export RPC_URL="https://alfajores-forno.celo-testnet.org"

# Run oracle
node oracle.js --vault 0x1234567890123456789012345678901234567890 --fid 12345
```

**Important:** Ensure the oracle wallet has:
- Sufficient gas tokens (CELO)
- Authorization in the vault contract (`setOracle()` must be called first)

## Aura Computation

The aura score (0-200) is computed using weighted normalization:

```
aura = w1*norm(followers) + w2*norm(followerDelta) + w3*norm(avgLikes) + w4*verification - spamPenalty
```

### Weights

- Followers: 35%
- Follower Delta: 25%
- Average Likes: 30%
- Verification: 10%

### Normalization

Log-based normalization maps raw counts to 0-200 range:

- **Followers**: 10 → 100,000
- **Follower Delta**: 0 → 1,000
- **Average Likes**: 1 → 1,000

### Metrics Source (Free Tier Compatible)

The oracle is designed to work with **Neynar's free tier API** (1000 requests/day), making it accessible without premium subscriptions.

#### API Endpoint Used

```
GET https://api.neynar.com/v2/farcaster/user/bulk?fids={fid}
```

This endpoint is available in the free tier and provides:

| Metric | Source | How It's Used |
|--------|--------|---------------|
| **Follower Count** | `user.follower_count` | Direct value used in normalization |
| **Verification Status** | `user.power_badge` | Adds +20 bonus if verified |
| **Neynar Score** | `user.score` or `user.experimental.neynar_user_score` | Used to estimate engagement |
| **Following Count** | `user.following_count` | Used to calculate follower/following ratio |

#### Derived Metrics (Free Tier Workaround)

Since the free tier doesn't include cast/engagement endpoints, we derive these metrics:

**Average Likes Estimation:**
```javascript
estimatedAvgLikes = neynarScore * 100
// Neynar score (0-1) represents overall engagement quality
// Scaled to 0-100 to represent typical like counts
```

**Follower Delta Estimation:**
```javascript
followRatio = followerCount / followingCount
growthFactor = min(neynarScore * followRatio * 0.01, 0.05)
followerDelta = followerCount * growthFactor
// Higher score + better ratio = estimated growth
```

#### Why This Works

- **Neynar Score** is a composite metric that already considers engagement, activity, and network effects
- Accounts with high scores typically have good engagement (likes, replies, recasts)
- The follower/following ratio helps identify organic vs. follow-back accounts
- This approach provides reasonable aura estimates without premium API access

#### Limitations

- Engagement metrics are estimates, not real-time cast data
- Follower delta is calculated, not tracked historically
- May not capture sudden viral moments or recent activity spikes

For production systems requiring precise engagement data, consider upgrading to Neynar's premium tier or implementing historical tracking.

### Spam Penalty

Accounts with >10k followers but <10 avg likes receive a -20 penalty to discourage bot accounts.

## Testing

### Run Test Suite

The oracle includes a comprehensive test suite that validates all core functions:

```bash
npm test
```

Or run directly:

```bash
node test-oracle.js
```

**Tests included:**
- ✅ Clamp function (boundary validation)
- ✅ Log-based normalization (0-200 range mapping)
- ✅ Mock metrics fetching
- ✅ Aura computation with various scenarios
- ✅ Spam penalty detection
- ✅ Edge cases (low followers, high followers, bot-like accounts)

**Expected output:**
```
🧪 Testing AuraFi Oracle Functions

Test 1: Clamp function
✅ Clamp tests passed

Test 2: Normalize function
✅ Normalize tests passed

Test 3: Fetch metrics (mock mode)
✅ Fetch metrics test passed

Test 4: Compute aura
✅ Aura computed: 136

Test 5: Different metric scenarios
✅ Scenario tests passed

🎉 All tests passed!
```

### Manual Testing

Test with a real Farcaster account (no transaction):

```bash
# Test with your own FID
node oracle.js --vault 0x0000000000000000000000000000000000000000 --fid YOUR_FID --dry-run

# Test with a known account (e.g., FID 1398844)
node oracle.js --vault 0x0000000000000000000000000000000000000000 --fid 1398844 --dry-run
```

## IPFS Evidence

Each aura update includes an IPFS hash containing:

```json
{
  "fid": "12345",
  "followerCount": 5000,
  "followerDelta": 150,
  "avgLikes": 45,
  "isVerified": true,
  "neynarScore": 0.5,
  "username": "creator",
  "displayName": "Creator Name",
  "timestamp": 1234567890,
  "aura": 125,
  "computation": {
    "weights": { ... },
    "normParams": { ... },
    "version": "1.0.0"
  }
}
```

This provides an audit trail for all aura updates. The `neynarScore` field shows the raw Neynar user score used for engagement estimation.

## Production Deployment

For production use:

1. **Secure Key Management**: Use a hardware wallet or key management service for `ORACLE_PRIVATE_KEY`
2. **Automated Execution**: Set up a cron job or scheduled task to run the oracle periodically
3. **Monitoring**: Log all executions and set up alerts for failures
4. **Rate Limiting**: Respect API rate limits (Neynar, Pinata)
5. **Cooldown**: The contract enforces a 6-hour cooldown between updates

### Example Cron Job

Update aura every 6 hours:

```bash
0 */6 * * * cd /path/to/oracle && node oracle.js --vault 0x... --fid 12345 >> oracle.log 2>&1
```

## Troubleshooting

### Common Issues

#### "ORACLE_PRIVATE_KEY environment variable not set"

**Cause:** The oracle private key is not configured.

**Solution:**
```bash
# Generate a new wallet
cast wallet new

# Add to .env.local
echo "ORACLE_PRIVATE_KEY=0x..." >> .env.local
```

#### "CreatorVault ABI not found. Run `forge build` first."

**Cause:** Contract artifacts are missing.

**Solution:**
```bash
# Navigate to project root
cd ..

# Compile contracts
forge build

# Return to oracle directory
cd oracle
```

#### "User with FID {fid} not found"

**Cause:** Invalid Farcaster ID or user doesn't exist.

**Solution:**
- Verify the FID is correct
- Check the user exists on Farcaster
- Try with a known FID like `1398844`

#### "CooldownNotElapsed" error

**Cause:** The vault contract enforces a 6-hour cooldown between updates.

**Solution:**
- Wait for the cooldown period to elapse
- Check last update time: `cast call <vault> "lastUpdateTime()(uint256)"`
- Use `--dry-run` to test without sending transactions

#### API Rate Limits (Neynar)

**Cause:** Exceeded free tier limit (1000 requests/day).

**Solutions:**
- Use `--mock` mode for testing
- Implement request caching
- Upgrade to Neynar premium tier
- Spread oracle updates across the day

#### "Insufficient funds for gas"

**Cause:** Oracle wallet doesn't have enough CELO for gas.

**Solution:**
```bash
# Check balance
cast balance <oracle-address> --rpc-url $RPC_URL

# Get testnet CELO from faucet
# Celo Alfajores: https://faucet.celo.org/alfajores
```

#### IPFS Pinning Fails

**Cause:** Pinata credentials not set or invalid.

**Solution:**
- The oracle will continue with mock IPFS hashes
- To fix: Add valid Pinata credentials to `.env.local`
- Verify credentials at [Pinata Dashboard](https://app.pinata.cloud/)

### Getting Help

If you encounter issues not covered here:

1. Check the oracle logs for detailed error messages
2. Run with `--dry-run` to test without on-chain transactions
3. Verify all environment variables are set correctly
4. Ensure contracts are compiled (`forge build`)
5. Test with `--mock` mode to isolate API issues

## Security Considerations

- **Private Key**: Never commit `ORACLE_PRIVATE_KEY` to version control
- **API Keys**: Rotate API keys regularly
- **Audit Trail**: All updates are logged on-chain with IPFS evidence
- **Access Control**: Only the authorized oracle address can update aura
- **Cooldown**: Prevents spam and manipulation attempts

## Future Enhancements

- Multi-oracle consensus mechanism
- Historical follower tracking for accurate deltas
- Additional social signals (casts, replies, recasts)
- Automated anomaly detection
- Dashboard for monitoring oracle health
#   a u r a f y  
 