# Manual Deployment Guide - AuraFi Protocol

Complete step-by-step guide for manually deploying and testing the AuraFi protocol using Anvil.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Setup Anvil](#setup-anvil)
3. [Deploy Contracts](#deploy-contracts)
4. [Create Vault](#create-vault)
5. [Bootstrap Creator](#bootstrap-creator)
6. [Set Initial Aura](#set-initial-aura)
7. [Fan Minting](#fan-minting)
8. [Test Aura Updates](#test-aura-updates)
9. [Test Forced Burn](#test-forced-burn)
10. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools

```bash
# Verify Foundry is installed
forge --version
cast --version
anvil --version

# Build contracts
cd /path/to/aurafi
forge build
```

---

## Setup Anvil

### Terminal 1: Start Anvil

```bash
# Fork Ethereum Sepolia (recommended)
anvil --fork-url https://ethereum-sepolia-rpc.publicnode.com --chain-id 11155111
```

**Keep this terminal running!** Anvil will output 10 pre-funded accounts.

### Terminal 2: Set Environment

```bash
export RPC_URL="http://localhost:8545"
export PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

# Verify connection
cast chain-id --rpc-url $RPC_URL
```

---

## Deploy Contracts

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY \
  -vv

# Save addresses
cat deployments.json
TREASURY="0x..."  # From output
ORACLE="0x..."    # From output
FACTORY="0x..."   # From output
```

---

## Create Vault

```bash
# Set creator
CREATOR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"

# Create vault
cast send $FACTORY \
  "createVault(string,string,address,uint256)" \
  "CreatorToken" "CRTR" $CREATOR "1000000000000000000000" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Get vault address from logs
VAULT="0x..."  # From VaultCreated event

# Get token address
RAW_TOKEN=$(cast call $VAULT "token()" --rpc-url $RPC_URL)
TOKEN="0x${RAW_TOKEN:26:40}"

echo "Vault: $VAULT"
echo "Token: $TOKEN"
```

---

## Bootstrap Creator

```bash
CREATOR_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

cast send $VAULT \
  "bootstrapCreatorStake()" \
  --value 100ether \
  --rpc-url $RPC_URL \
  --private-key $CREATOR_KEY

# Verify
cast call $VAULT "stage()" --rpc-url $RPC_URL
# Should return: 1
```

---

## Set Initial Aura

```bash
cast send $ORACLE \
  "pushAura(address,uint256,string)" \
  $VAULT 136 "QmMockInitialMetrics123" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check peg
PEG=$(cast call $VAULT "getPeg()" --rpc-url $RPC_URL)
echo "Peg: $(cast to-unit $PEG ether) CELO"

# Check supply cap
CAP=$(cast call $VAULT "getCurrentSupplyCap()" --rpc-url $RPC_URL)
echo "Supply cap: $(cast to-unit $CAP ether) tokens"
```

**Expected:** Peg ~1.18 CELO, Cap ~1270 tokens

---

## Fan Minting

```bash
FAN1="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
FAN1_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

# Mint 50 tokens
cast send $VAULT \
  "mintTokens(uint256)" \
  "50000000000000000000" \
  --value 90ether \
  --rpc-url $RPC_URL \
  --private-key $FAN1_KEY

# Check balance
FAN1_BAL=$(cast call $TOKEN "balanceOf(address)(uint256)" $FAN1 --rpc-url $RPC_URL | awk '{print $1}')
echo "Fan1 balance: $(cast to-unit $FAN1_BAL ether) tokens"
```

---

## Test Aura Updates

```bash
# Fast-forward 6 hours
cast rpc evm_increaseTime 21601 --rpc-url $RPC_URL
cast rpc evm_mine --rpc-url $RPC_URL

# Increase aura
cast send $ORACLE \
  "pushAura(address,uint256,string)" \
  $VAULT 175 "QmMockIncreasedMetrics456" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# Check new peg
NEW_PEG=$(cast call $VAULT "getPeg()" --rpc-url $RPC_URL)
echo "New peg: $(cast to-unit $NEW_PEG ether) CELO"
```

---

## Test Forced Burn

To test forced burn, supply must exceed cap:

```bash
# 1. Mint more tokens at high cap (aura 175)
cast send $VAULT \
  "mintTokens(uint256)" \
  "350000000000000000000" \
  --value 800ether \
  --rpc-url $RPC_URL \
  --private-key $FAN1_KEY

# 2. Lower aura (cap drops below supply)
cast rpc evm_increaseTime 21601 --rpc-url $RPC_URL
cast rpc evm_mine --rpc-url $RPC_URL

cast send $ORACLE \
  "pushAura(address,uint256,string)" \
  $VAULT 20 "QmMockLowAura" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 3. Trigger forced burn
cast send $VAULT \
  "checkAndTriggerForcedBurn()" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY

# 4. Execute after grace period
cast rpc evm_increaseTime 86400 --rpc-url $RPC_URL
cast rpc evm_mine --rpc-url $RPC_URL

cast send $VAULT \
  "executeForcedBurn(uint256)" \
  100 \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

---

## Troubleshooting

### CooldownNotElapsed
```bash
cast rpc evm_increaseTime 21601 --rpc-url $RPC_URL
cast rpc evm_mine --rpc-url $RPC_URL
```

### InsufficientCollateral
```bash
# Increase payment amount
--value 100ether  # Instead of 90ether
```

### Token balance error
```bash
# Use correct signature
cast call $TOKEN "balanceOf(address)(uint256)" $ADDRESS --rpc-url $RPC_URL | awk '{print $1}'
```

---

## Quick Reference

```bash
# Check vault state
cast call $VAULT "getVaultState()" --rpc-url $RPC_URL

# Check aura
cast call $VAULT "getCurrentAura()" --rpc-url $RPC_URL

# Check peg
cast call $VAULT "getPeg()" --rpc-url $RPC_URL

# Check supply
cast call $VAULT "totalSupply()" --rpc-url $RPC_URL

# Convert wei to ether
cast to-unit $VALUE ether

# Fast-forward time
cast rpc evm_increaseTime $SECONDS --rpc-url $RPC_URL
cast rpc evm_mine --rpc-url $RPC_URL
```

### Anvil Accounts

| Role | Address | Private Key |
|------|---------|-------------|
| Deployer | 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | 0xac0974... |
| Creator | 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 | 0x59c6995... |
| Fan1 | 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC | 0x5de4111... |
| Fan2 | 0x90F79bf6EB2c4f870365E785982E1f101E93b906 | 0x7c85211... |

---

**Version**: 1.0.0  
**Last Updated**: 2025-01-25

🎉 **Happy Testing!**
