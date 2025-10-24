# Oracle Testing Guide

## Overview

This guide explains how to test the AuraOracle workflow using the provided scripts.

## Scripts

### 1. `oracle.js` - Write Data to Contract

This script acts as the authorized oracle and writes aura data to the AuraOracle contract.

**Usage:**
```bash
node oracle.js --vault <vault-address> --fid <farcaster-id> [options]
```

**Options:**
- `--vault <address>` - Vault contract address (required)
- `--fid <id>` - Creator's Farcaster ID (required)
- `--mock` - Use mock data instead of fetching from Farcaster
- `--dry-run` - Compute aura but don't send transaction

**Example:**
```bash
# Push data to vault with mock metrics
node oracle.js --vault 0x0000000000000000000000000000000000000001 --fid 12345 --mock
```

### 2. `test-oracle.js` - Read Data from Contract

This script reads data back from the AuraOracle contract to verify it was written correctly.

**Usage:**
```bash
# Run all tests with default vault address
node test-oracle.js

# Query specific vault address
node test-oracle.js <vault-address>
```

**Examples:**
```bash
# Test with default address
node test-oracle.js

# Query specific vault
node test-oracle.js 0x0000000000000000000000000000000000000001

# Query another vault
node test-oracle.js 0x1234567890123456789012345678901234567890
```

## Complete Workflow Test

### Step 1: Push Data (Write)
```bash
node oracle.js --vault 0x0000000000000000000000000000000000000001 --fid 12345 --mock
```

**Expected Output:**
- ✅ Metrics fetched
- ✅ Aura computed (e.g., 136)
- ✅ Data pinned to IPFS
- ✅ Transaction sent to AuraOracle contract

### Step 2: Verify Data (Read)
```bash
node test-oracle.js 0x0000000000000000000000000000000000000001
```

**Expected Output:**
```json
{
  "vaultAddress": "0x0000000000000000000000000000000000000001",
  "aura": "136",
  "ipfsHash": "QmXbCZGCK65u5UidFve2YzkLxXK45Rs55RQbvgp6zc6SkV",
  "lastUpdate": "1761340312",
  "lastUpdateDate": "2025-10-24T21:11:52.000Z"
}
```

## Contract Functions Tested

### Write Operations (oracle.js)
- `pushAura(vault, aura, ipfsHash)` - Writes aura data to contract

### Read Operations (test-oracle.js)
- `getAura(vault)` - Returns the aura score for a vault
- `getIpfsHash(vault)` - Returns the IPFS hash for a vault
- `getLastUpdateTimestamp(vault)` - Returns the last update timestamp

## Environment Variables

Required in `.env.local`:

```env
# Oracle Contract
ORACLE_CONTRACT_ADDRESS=0xa585e63cfAeFc513198d70FbA741B22d8116C2d0

# Oracle Wallet (for writing)
ORACLE_PRIVATE_KEY=your_private_key_here

# Network
RPC_URL=https://rpc.ankr.com/celo_sepolia

# IPFS (Pinata)
PINATA_JWT=your_pinata_jwt_here
PINATA_GATEWAY=https://indigo-naval-wolverine-789.mypinata.cloud

# Farcaster API (optional, for live data)
NEYNAR_API_KEY=your_neynar_api_key_here
```

## Testing Different Scenarios

### Test 1: Vault with Data
```bash
node test-oracle.js 0x0000000000000000000000000000000000000001
```
Expected: Returns aura score, IPFS hash, and timestamp

### Test 2: Vault without Data
```bash
node test-oracle.js 0x0000000000000000000000000000000000000002
```
Expected: Returns aura=0, empty IPFS hash, lastUpdate="Never"

### Test 3: Query Multiple Vaults
```bash
# Vault 1
node test-oracle.js 0x0000000000000000000000000000000000000001

# Vault 2
node test-oracle.js 0x0000000000000000000000000000000000000002

# Vault 3
node test-oracle.js 0x0000000000000000000000000000000000000003
```

## Troubleshooting

### Error: "ORACLE_CONTRACT_ADDRESS environment variable not set"
- Make sure `.env.local` exists in the `oracle/` directory
- Verify `ORACLE_CONTRACT_ADDRESS` is set correctly

### Error: "AuraOracle ABI not found"
- Run `forge build` in the project root to compile contracts

### Error: "execution reverted (unknown custom error)"
- Check if the cooldown period (6 hours) has elapsed since last update
- Verify the oracle wallet has permission to call `pushAura`

### Error: "network does not support ENS"
- Make sure you're using a valid Ethereum address (0x...)
- Don't use ENS names or placeholder text like "0xYourVaultAddress"

## Success Indicators

✅ **Write Success:**
- Transaction confirmed
- Gas used displayed
- No errors

✅ **Read Success:**
- Aura score matches what was written
- IPFS hash is returned
- Last update timestamp is recent

## Notes

- The oracle wallet must be authorized in the AuraOracle contract
- Cooldown period is 6 hours between updates for the same vault
- Mock mode doesn't require Farcaster API keys
- Read operations don't require a wallet (read-only)
