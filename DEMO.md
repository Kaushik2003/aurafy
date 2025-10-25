# AuraFi Protocol - Demo Guide

Complete guide for demonstrating the AuraFi protocol end-to-end, including both automated mock testing and real testnet integration.

## Table of Contents

1. [Overview](#overview)
2. [Quick Start - Mock Demo](#quick-start---mock-demo)
3. [Real Testnet Demo](#real-testnet-demo)
4. [Oracle Integration](#oracle-integration)
5. [Edge Cases & Troubleshooting](#edge-cases--troubleshooting)
6. [Production Considerations](#production-considerations)

---

## Overview

The AuraFi demo demonstrates the complete lifecycle of a creator vault:

- **Contract Deployment**: Treasury, Oracle, Factory
- **Creator Bootstrapping**: Initial stake to unlock stage 1
- **Oracle Updates**: Aura score updates from Farcaster metrics
- **Fan Minting**: Token minting with dynamic peg pricing
- **Peg Dynamics**: Peg increases/decreases based on aura
- **Forced Contraction**: Supply cap enforcement when aura drops
- **Liquidation**: Health restoration when undercollateralized

### Two Demo Modes

1. **Mock Mode** (Automated): Uses hardcoded aura values, no external dependencies
2. **Testnet Mode** (Real): Integrates with oracle.js for live Farcaster data

---

## Quick Start - Mock Demo

Run the automated demo with mock oracle data:

```bash
# Build contracts
forge build

# Option 1: Local simulation (no private key needed, no real transactions)
forge script script/Demo.s.sol -vvv

# Option 2: Deploy to testnet (requires private key and testnet CELO)
export RPC_URL="https://rpc.ankr.com/celo_sepolia"
export PRIVATE_KEY="0x..."  # Your private key
forge script script/Demo.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY -vvv

# Option 3: Using .env file (recommended for testnet)
# Create .env file with:
# RPC_URL=https://alfajores-forno.celo-testnet.org
# PRIVATE_KEY=0x...
source .env
forge script script/Demo.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY -vvv
```

**Note**: The local simulation (Option 1) is perfect for testing the flow without spending gas or needing testnet funds. It runs entirely in a local EVM and shows you exactly what would happen on-chain.

### What the Mock Demo Does

1. **Deploys** all contracts (Treasury, Oracle, Factory)
2. **Creates** a vault for demo creator (FID: 12345)
3. **Bootstraps** 100 CELO creator stake → unlocks stage 1
4. **Pushes** initial aura (136) via mock oracle
5. **Mints** 50 tokens for fan1 at initial peg
6. **Updates** aura to 175 (growth scenario) → peg increases
7. **Mints** 30 tokens for fan2 at higher peg
8. **Drops** aura to 40 → triggers forced burn
9. **Executes** forced burn after grace period
10. **Crashes** aura to 20 → triggers liquidation
11. **Liquidates** vault to restore health

### Expected Output

```
========================================
   AuraFi Protocol - Demo Script
========================================

=== PHASE 1: Deploy Contracts ===
Treasury deployed: 0x...
AuraOracle deployed: 0x...
VaultFactory deployed: 0x...

=== PHASE 2: Bootstrap Creator Stake ===
Vault created for creator: 0x...
Creator bootstrapped with: 100 CELO
Stage unlocked: 1

=== PHASE 3: Initial Oracle Update (Mock) ===
Aura: 136
Peg: 1.18 CELO
Supply cap: 1270 tokens

... (continues through all phases)
```

---

## Real Testnet Demo

For testing with real Farcaster data on Celo Alfajores testnet.

### Prerequisites

1. **Funded Accounts**
   ```bash
   # Get testnet CELO from faucet
   # https://faucet.celo.org/celo-sepolia
   # Typically gives 1-5 CELO per request
   
   # Realistic testnet needs:
   # - Deployer account: ~0.5 CELO for deployment gas
   # - Oracle account: ~0.1 CELO for oracle updates
   # - Testing accounts: ~5-10 CELO total for small-scale testing
   
   # NOTE: You won't get 100 CELO from faucet!
   # See "Testnet Testing Strategies" below for solutions
   ```

2. **Environment Setup**
   ```bash
   # Root .env (for Foundry scripts)
   RPC_URL="https://rpc.ankr.com/celo_sepolia"
   PRIVATE_KEY="0x..."  # Deployer private key (64 hex chars without 0x prefix)
   
   # oracle/.env.local (for oracle script)
   NEYNAR_API_KEY="your_neynar_key"
   PINATA_JWT="your_pinata_jwt"
   PINATA_GATEWAY="https://your-gateway.mypinata.cloud"
   ORACLE_PRIVATE_KEY="0x..."  # Oracle account private key (with 0x prefix)
   ORACLE_CONTRACT_ADDRESS=""  # Will be filled after deployment
   RPC_URL="https://rpc.ankr.com/celo_sepolia"
   ```

3. **API Keys**
   - **Neynar API**: Get free key at https://neynar.com (100 requests/day free tier)
   - **Pinata**: Get JWT at https://pinata.cloud (1GB storage free tier)

4. **Private Key Security**
   - **NEVER** commit private keys to git
   - Add `.env` and `oracle/.env.local` to `.gitignore`
   - Use separate accounts for testing (not your main wallet)
   - For production, use hardware wallets or key management services

### Testnet Testing Strategies

Since the Celo Sepolia faucet only provides 1-5 CELO per request, you have several options:

#### Option A: Modify Stage Requirements (Recommended for Testing)

Create a custom deployment script with lower stage requirements:

```solidity
// script/DeployTestnet.s.sol
// Copy Deploy.s.sol and modify the factory initialization:

// After deploying factory, set custom stage configs:
factory.setStageConfig(vault, 1, 1 ether, 50 ether);    // Stage 1: 1 CELO, 50 tokens
factory.setStageConfig(vault, 2, 3 ether, 250 ether);   // Stage 2: 3 CELO, 250 tokens
factory.setStageConfig(vault, 3, 8 ether, 950 ether);   // Stage 3: 8 CELO, 950 tokens
factory.setStageConfig(vault, 4, 18 ether, 3450 ether); // Stage 4: 18 CELO, 3450 tokens
```

#### Option B: Use Multiple Faucet Requests

```bash
# Request from faucet multiple times (wait between requests)
# Use different browsers/IPs if rate-limited
# Accumulate 10-20 CELO over time for more realistic testing
```

#### Option C: Local Fork Testing

```bash
# Fork mainnet/testnet with funded accounts
anvil --fork-url https://rpc.ankr.com/celo_sepolia

# Then use anvil's default funded accounts (10000 ETH each)
forge script script/Demo.s.sol --rpc-url http://localhost:8545 --broadcast
```

#### Option D: Minimal Testing Flow

Test with minimal amounts:
- Bootstrap with 1 CELO (modify stage 1 requirement)
- Mint 5-10 tokens per fan
- Test oracle updates with small supply
- Verify core mechanics work at small scale

### Step-by-Step Testnet Demo

#### Step 0: Adjust Stage Requirements (if needed)

If you have limited testnet CELO, modify the stage requirements before deployment:

```bash
# Edit contracts/VaultFactory.sol _initializeDefaultStages() function
# Change line ~140-148 to lower values:
CreatorVault(vault).setStageConfig(1, 1e18, 50e18);      // 1 CELO, 50 tokens
CreatorVault(vault).setStageConfig(2, 3e18, 250e18);     // 3 CELO, 250 tokens
CreatorVault(vault).setStageConfig(3, 8e18, 950e18);     // 8 CELO, 950 tokens
CreatorVault(vault).setStageConfig(4, 18e18, 3450e18);   // 18 CELO, 3450 tokens

# Rebuild
forge build
```

#### Step 1: Deploy Contracts

```bash
# Deploy all contracts
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify

# Note the deployed addresses from output
# Update oracle/.env.local with ORACLE_CONTRACT_ADDRESS
```

#### Step 2: Create Vault

```bash
# Using cast to interact with factory
FACTORY_ADDRESS="0x..."  # From deployment
CREATOR_ADDRESS="0x..."  # Your creator account
TOKEN_NAME="Creator Token"
TOKEN_SYMBOL="CRTR"
BASE_CAP="1000000000000000000000"  # 1000 tokens (in wei)

# Create vault returns (vault, token) addresses
cast send $FACTORY_ADDRESS \
  "createVault(string,string,address,uint256)" \
  "$TOKEN_NAME" "$TOKEN_SYMBOL" $CREATOR_ADDRESS $BASE_CAP \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Get vault and token addresses from logs
VAULT_ADDRESS="0x..."
TOKEN_ADDRESS="0x..."
```

#### Step 3: Bootstrap Creator Stake

```bash
# Creator deposits CELO to unlock stage 1
# Amount depends on your stage configuration:
# - Default: 100 CELO
# - Testnet-friendly: 1 CELO (if you modified stage requirements)

BOOTSTRAP_AMOUNT="1ether"  # Adjust based on your stage 1 requirement

cast send $VAULT_ADDRESS \
  "bootstrapCreatorStake()" \
  --value $BOOTSTRAP_AMOUNT \
  --rpc-url $RPC_URL \
  --private-key $CREATOR_PRIVATE_KEY

# Verify stage unlocked
cast call $VAULT_ADDRESS "stage()" --rpc-url $RPC_URL
# Should return: 1
```

#### Step 4: Initial Oracle Update

**⚠️ CRITICAL: Oracle must push data before any minting**

```bash
cd oracle

# Test oracle with dry run first
node oracle.js --vault $VAULT_ADDRESS --fid $CREATOR_FID --dry-run

# Push real aura update
node oracle.js --vault $VAULT_ADDRESS --fid $CREATOR_FID

# Verify aura was set
cast call $ORACLE_ADDRESS "getAura(address)" $VAULT_ADDRESS --rpc-url $RPC_URL
```

**Expected Output:**
```
🌟 AuraFi Oracle
================

Vault: 0x...
Creator FID: 12345
Mode: Live

📡 Fetching Farcaster metrics...
✅ Metrics fetched for @username

📊 Aura Computation:
  Followers: 5000 → 156.23 (weight: 0.35)
  Follower Δ: 150 → 98.45 (weight: 0.25)
  Avg Likes: 45 → 112.67 (weight: 0.30)
  Verified: true → +20.00
  Final Aura: 136

📌 Pinning metrics to IPFS...
📌 Pinned to IPFS: QmXxx...

📤 Sending pushAura transaction...
✅ Transaction confirmed in block 12345678
```

#### Step 5: Fan Minting

```bash
# Calculate required collateral: qty * peg * MIN_CR + fee
# For testnet with limited funds, mint smaller amounts

# Get current peg
PEG=$(cast call $VAULT_ADDRESS "getPeg()" --rpc-url $RPC_URL)
echo "Current peg: $PEG wei"

# Mint 5 tokens (testnet-friendly amount)
QTY="5000000000000000000"  # 5 tokens in wei

# Calculate required payment
# Example: 5 tokens * 1.18 CELO peg * 1.5 MIN_CR = 8.85 CELO
# Plus 0.5% fee = ~8.9 CELO total
PAYMENT="9000000000000000000"  # 9 CELO (with buffer)

cast send $VAULT_ADDRESS \
  "mintTokens(uint256)" \
  $QTY \
  --value $PAYMENT \
  --rpc-url $RPC_URL \
  --private-key $FAN_PRIVATE_KEY

# Verify mint
cast call $TOKEN_ADDRESS "balanceOf(address)" $FAN_ADDRESS --rpc-url $RPC_URL
```

#### Step 6: Oracle Update - Growth Scenario

**Wait 6 hours for cooldown** (or fast-forward in local testing)

```bash
# Creator gains followers, engagement increases
# Oracle detects higher metrics

node oracle.js --vault $VAULT_ADDRESS --fid $CREATOR_FID

# Aura increases → peg increases
# New mints will pay higher price per token
```

#### Step 7: More Minting at Higher Peg

```bash
# Fan2 mints at new higher peg
# Same process as Step 5, but peg is now higher
# Demonstrates dynamic pricing based on creator performance
```

#### Step 8: Oracle Update - Decline Scenario

```bash
# Simulate creator decline (or wait for real metrics drop)
# If using mock mode for testing:

node oracle.js --vault $VAULT_ADDRESS --fid $CREATOR_FID --mock

# Manually edit oracle.js to return lower aura (40)
# Or wait for real metrics to decline
```

#### Step 9: Forced Burn

```bash
# Check if forced burn was triggered
cast call $VAULT_ADDRESS "pendingForcedBurn()" --rpc-url $RPC_URL

# If > 0, wait for grace period (24 hours)
cast call $VAULT_ADDRESS "forcedBurnDeadline()" --rpc-url $RPC_URL

# After grace period, execute burn
cast send $VAULT_ADDRESS "executeForcedBurn()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

#### Step 10: Liquidation

```bash
# If health drops below 120%, anyone can liquidate

# Check health
cast call $VAULT_ADDRESS "calculateHealth()" --rpc-url $RPC_URL

# Liquidate by injecting CELO
cast send $VAULT_ADDRESS \
  "liquidate()" \
  --value 5ether \
  --rpc-url $RPC_URL \
  --private-key $LIQUIDATOR_PRIVATE_KEY
```

---

## Oracle Integration

### How Oracle Works

1. **Fetches** Farcaster metrics via Neynar API
2. **Computes** aura score (0-200) using weighted formula
3. **Pins** metrics + computation to IPFS via Pinata
4. **Pushes** aura + IPFS hash to AuraOracle contract
5. **Enforces** 6-hour cooldown between updates

### Oracle Data Flow

```
Farcaster API (Neynar)
    ↓
oracle.js (compute aura)
    ↓
IPFS (Pinata) ← metrics evidence
    ↓
AuraOracle.pushAura(vault, aura, ipfsHash)
    ↓
CreatorVault reads aura dynamically
    ↓
Peg & Supply Cap adjust automatically
```

### Oracle Requirements

**CRITICAL**: Vault **MUST** have aura data before any minting

- Initial aura = 0 (not set)
- Peg calculation requires aura > 0
- **First oracle update must happen before first mint**

### Oracle Cooldown

- **6 hours** between updates per vault
- Prevents manipulation/spam
- Enforced by AuraOracle contract
- Plan oracle updates accordingly

### Mock vs Live Oracle

**Mock Mode** (`--mock` flag):
- Uses hardcoded metrics
- No API keys needed
- Good for testing flow
- Aura always returns ~136

**Live Mode** (default):
- Fetches real Farcaster data
- Requires NEYNAR_API_KEY
- Aura varies based on actual metrics
- Production-ready

---

## Edge Cases & Troubleshooting

### Edge Case 1: Zero Aura

**Problem**: Vault created but oracle never updates
**Symptom**: `getPeg()` returns 0 or reverts
**Solution**: Always push initial aura immediately after vault creation

```bash
# Right after createVault:
node oracle.js --vault $VAULT_ADDRESS --fid $FID
```

### Edge Case 2: Cooldown Violation

**Problem**: Trying to update aura too soon
**Symptom**: Transaction reverts with `CooldownNotElapsed()`
**Solution**: Wait 6 hours between updates

```bash
# Check last update time
cast call $ORACLE_ADDRESS "getLastUpdateTimestamp(address)" $VAULT_ADDRESS --rpc-url $RPC_URL

# Calculate next allowed update
# lastUpdate + 21600 seconds (6 hours)
```

### Edge Case 3: Supply Exceeds Cap

**Problem**: Aura drops, supply > new cap
**Symptom**: Minting reverts with `ExceedsSupplyCap()`
**Solution**: Trigger forced burn

```bash
# Anyone can trigger
cast send $VAULT_ADDRESS "checkAndTriggerForcedBurn()" --rpc-url $RPC_URL --private-key $ANY_KEY

# Wait 24 hours grace period
# Then execute burn
cast send $VAULT_ADDRESS "executeForcedBurn()" --rpc-url $RPC_URL --private-key $ANY_KEY
```

### Edge Case 4: Health Below MIN_CR

**Problem**: Redemption would drop health below 150%
**Symptom**: `redeemTokens()` reverts with `HealthTooLow()`
**Solution**: Either:
1. Redeem smaller amount
2. Wait for aura increase (peg increases → health improves)
3. Creator adds more collateral

### Edge Case 5: Liquidation Not Profitable

**Problem**: Liquidator payment too small
**Symptom**: Transaction reverts with `InsufficientPayment()`
**Solution**: Inject at least 0.01 CELO

```bash
# Minimum payment
cast send $VAULT_ADDRESS "liquidate()" --value 0.01ether --rpc-url $RPC_URL --private-key $KEY
```

### Edge Case 6: Oracle Key Compromise

**Problem**: Oracle private key leaked
**Symptom**: Unauthorized aura updates
**Solution**: Rotate oracle address

```bash
# Owner updates oracle address
cast send $ORACLE_ADDRESS \
  "setOracleAddress(address)" \
  $NEW_ORACLE_ADDRESS \
  --rpc-url $RPC_URL \
  --private-key $OWNER_KEY

# Update oracle/.env.local with new key
```

### Edge Case 7: IPFS Pin Failure

**Problem**: Pinata API fails
**Symptom**: Oracle continues with mock hash
**Solution**: Check Pinata JWT and gateway

```bash
# Test Pinata connection
curl -X POST "https://api.pinata.cloud/data/testAuthentication" \
  -H "Authorization: Bearer $PINATA_JWT"

# Should return: {"message":"Congratulations! You are communicating with the Pinata API!"}
```

### Edge Case 8: Neynar API Rate Limit

**Problem**: Too many oracle calls
**Symptom**: API returns 429 error
**Solution**: 
- Free tier: 100 requests/day
- Respect 6-hour cooldown
- Upgrade Neynar plan if needed

### Edge Case 9: Gas Price Spike

**Problem**: Oracle transaction fails due to low gas
**Symptom**: Transaction pending forever
**Solution**: Increase gas price in oracle.js

```javascript
// In oracle.js, add gas options:
const tx = await oracleContract.pushAura(vaultAddress, aura, ipfsHash, {
    gasLimit: 500000,
    maxFeePerGas: ethers.parseUnits('10', 'gwei'),
    maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei')
});
```

### Edge Case 10: Wrong FID

**Problem**: Oracle fetches wrong creator's metrics
**Symptom**: Aura doesn't match expected creator
**Solution**: Verify FID matches vault creator

```bash
# Get vault's FID
cast call $FACTORY_ADDRESS "vaultFid(address)" $VAULT_ADDRESS --rpc-url $RPC_URL

# Ensure oracle.js uses same FID
```

---

## Production Considerations

### Security

1. **Oracle Key Management**
   - Use hardware wallet or KMS for oracle key
   - Rotate keys periodically
   - Monitor for unauthorized updates

2. **Access Control**
   - Only oracle address can push aura
   - Only owner can update oracle address
   - Only creator can bootstrap/unlock stages

3. **Rate Limiting**
   - 6-hour cooldown prevents spam
   - Consider additional off-chain rate limiting

### Monitoring

1. **Oracle Health**
   - Monitor oracle.js execution logs
   - Alert on failed updates
   - Track API quota usage (Neynar, Pinata)

2. **Vault Health**
   - Monitor health ratio for all vaults
   - Alert when approaching liquidation threshold
   - Track forced burn triggers

3. **Metrics**
   - Aura update frequency
   - Peg volatility
   - Liquidation events
   - Forced burn events

### Automation

1. **Scheduled Oracle Updates**
   ```bash
   # Cron job for regular updates (every 6 hours)
   0 */6 * * * cd /path/to/oracle && node oracle.js --vault $VAULT --fid $FID >> oracle.log 2>&1
   ```

2. **Multi-Vault Oracle**
   ```bash
   # Update all vaults in sequence
   for vault in $(cat vaults.txt); do
     fid=$(cast call $FACTORY "vaultFid(address)" $vault --rpc-url $RPC_URL)
     node oracle.js --vault $vault --fid $fid
     sleep 60  # Rate limit
   done
   ```

3. **Health Monitoring Bot**
   ```bash
   # Check all vaults for liquidation opportunities
   # Alert if health < 125%
   ```

### Scalability

1. **Oracle Batching**
   - Update multiple vaults in single transaction
   - Requires contract modification

2. **IPFS Optimization**
   - Use IPFS cluster for redundancy
   - Pin to multiple gateways
   - Consider Filecoin for long-term storage

3. **API Optimization**
   - Cache Farcaster metrics (respect cooldown)
   - Batch API requests where possible
   - Use webhooks for real-time updates

### Cost Optimization

1. **Gas Costs**
   - Oracle update: ~100k gas
   - At 5 gwei: ~0.0005 CELO per update
   - 4 updates/day: ~0.002 CELO/day per vault

2. **API Costs**
   - Neynar free tier: 100 requests/day
   - Pinata free tier: 1GB storage, 100k requests/month
   - Scale up as needed

### Disaster Recovery

1. **Oracle Failure**
   - Vaults continue operating with last known aura
   - Peg/cap calculations use stale data
   - Resume updates ASAP

2. **Contract Pause**
   - Owner can pause vault in emergency
   - Prevents minting/redemption/liquidation
   - Use for critical bugs only

3. **Data Recovery**
   - All metrics stored on IPFS
   - Audit trail via events
   - Can reconstruct state from chain data

---

## Testing Checklist

### Mock Demo
- [ ] Contracts deploy successfully
- [ ] Vault created with correct parameters
- [ ] Creator can bootstrap stake
- [ ] Oracle can push aura (mock)
- [ ] Peg calculates correctly
- [ ] Fan can mint tokens
- [ ] Aura increase → peg increase
- [ ] Aura decrease → forced burn trigger
- [ ] Grace period enforced
- [ ] Forced burn executes
- [ ] Liquidation triggers when health low
- [ ] Liquidator receives bounty

### Testnet Demo
- [ ] All contracts deployed and verified
- [ ] Oracle.js configured with API keys
- [ ] Initial aura pushed before first mint
- [ ] Real Farcaster metrics fetched
- [ ] Metrics pinned to IPFS
- [ ] Aura updates respect cooldown
- [ ] Multiple fans can mint
- [ ] Redemption works correctly
- [ ] Forced burn handles real scenario
- [ ] Liquidation restores health
- [ ] Events emitted correctly
- [ ] UI can read vault state

### Production Readiness
- [ ] Oracle key secured (hardware wallet/KMS)
- [ ] Monitoring alerts configured
- [ ] Automated oracle updates scheduled
- [ ] API quotas sufficient
- [ ] Gas price strategy defined
- [ ] Disaster recovery plan documented
- [ ] Multi-sig for owner functions
- [ ] Contracts audited
- [ ] Bug bounty program launched

---

## Practical Testnet Example (With Limited Funds)

Here's a complete realistic testnet flow with only ~10 CELO:

```bash
# 1. Get testnet CELO (repeat faucet requests to accumulate ~10 CELO)
# Visit: https://faucet.celo.org/celo-sepolia

# 2. Modify stage requirements in VaultFactory.sol
# Change _initializeDefaultStages() to use 1 CELO for stage 1

# 3. Deploy contracts (~0.5 CELO gas)
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --private-key $PRIVATE_KEY

# 4. Create vault with small baseCap
cast send $FACTORY_ADDRESS \
  "createVault(string,string,address,uint256)" \
  "Test Token" "TEST" $CREATOR_ADDRESS "100000000000000000000" \
  --rpc-url $RPC_URL --private-key $PRIVATE_KEY
# baseCap: 100 tokens (not 1000)

# 5. Bootstrap with 1 CELO
cast send $VAULT_ADDRESS "bootstrapCreatorStake()" \
  --value 1ether --rpc-url $RPC_URL --private-key $CREATOR_KEY

# 6. Push initial aura
node oracle/oracle.js --vault $VAULT_ADDRESS --fid $FID

# 7. Mint 5 tokens (~8.9 CELO)
cast send $VAULT_ADDRESS "mintTokens(uint256)" "5000000000000000000" \
  --value 9ether --rpc-url $RPC_URL --private-key $FAN_KEY

# 8. Test oracle update
# Wait 6 hours or use vm.warp in tests
node oracle/oracle.js --vault $VAULT_ADDRESS --fid $FID

# Total spent: ~10 CELO (achievable with faucet!)
```

This demonstrates all core features at a scale that's testable with faucet funds.

---

## Useful Commands

### Query Vault State
```bash
# Get comprehensive state
cast call $VAULT_ADDRESS "getVaultState()" --rpc-url $RPC_URL

# Individual queries
cast call $VAULT_ADDRESS "getCurrentAura()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "getPeg()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "totalSupply()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "totalCollateral()" --rpc-url $RPC_URL
cast call $VAULT_ADDRESS "stage()" --rpc-url $RPC_URL
```

### Query Oracle
```bash
# Get aura for vault
cast call $ORACLE_ADDRESS "getAura(address)" $VAULT_ADDRESS --rpc-url $RPC_URL

# Get IPFS hash
cast call $ORACLE_ADDRESS "getIpfsHash(address)" $VAULT_ADDRESS --rpc-url $RPC_URL

# Get last update time
cast call $ORACLE_ADDRESS "getLastUpdateTimestamp(address)" $VAULT_ADDRESS --rpc-url $RPC_URL
```

### Monitor Events
```bash
# Watch for aura updates
cast logs --address $ORACLE_ADDRESS --event "AuraUpdated(address,uint256,string,uint256)" --rpc-url $RPC_URL

# Watch for mints
cast logs --address $VAULT_ADDRESS --event "Minted(address,address,uint256,uint256,uint8,uint256)" --rpc-url $RPC_URL

# Watch for liquidations
cast logs --address $VAULT_ADDRESS --event "LiquidationExecuted(address,address,uint256,uint256,uint256)" --rpc-url $RPC_URL
```

---

## Support

For issues or questions:
- Check [SETUP.md](./SETUP.md) for environment setup
- Review [oracle/README.md](./oracle/README.md) for oracle details
- Check contract tests in `test/` directory
- Review Foundry docs: https://book.getfoundry.sh

---

**Demo Version**: 1.0.0  
**Last Updated**: 2025-10-25  
**Network**: Celo Alfajores Testnet
