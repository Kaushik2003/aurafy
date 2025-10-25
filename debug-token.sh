#!/bin/bash

echo "=== Complete Token Balance Diagnostic ==="
echo ""

# 1. Check environment
echo "1. Environment Check:"
echo "   RPC_URL: $RPC_URL"
echo "   VAULT: $VAULT"
echo "   FAN1: $FAN1"
echo ""

# 2. Verify connection
echo "2. Network Check:"
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL 2>&1)
echo "   Chain ID: $CHAIN_ID"
BLOCK=$(cast block-number --rpc-url $RPC_URL 2>&1)
echo "   Current block: $BLOCK"
echo ""

# 3. Check vault
echo "3. Vault Check:"
VAULT_CODE=$(cast code $VAULT --rpc-url $RPC_URL 2>&1)
if [[ "$VAULT_CODE" == "0x" ]]; then
    echo "   ❌ ERROR: Vault has no code!"
    exit 1
else
    echo "   ✅ Vault exists (${#VAULT_CODE} bytes)"
fi
echo ""

# 4. Get token address (multiple methods)
echo "4. Token Address Extraction:"

# Method A: Direct call
RAW_TOKEN=$(cast call $VAULT "token()" --rpc-url $RPC_URL 2>&1)
echo "   Raw response: $RAW_TOKEN"

# Method B: Try to decode
TOKEN_A=$(echo $RAW_TOKEN | cast --to-address 2>&1)
echo "   Method A (cast decode): $TOKEN_A"

# Method C: Manual extraction
if [[ ${#RAW_TOKEN} -eq 66 ]]; then
    TOKEN_B="0x${RAW_TOKEN:26:40}"
    echo "   Method B (manual): $TOKEN_B"
fi

# Use the one that looks valid
if [[ $TOKEN_A =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    TOKEN=$TOKEN_A
elif [[ $TOKEN_B =~ ^0x[a-fA-F0-9]{40}$ ]]; then
    TOKEN=$TOKEN_B
else
    echo "   ❌ ERROR: Could not extract valid token address"
    exit 1
fi

echo "   ✅ Using TOKEN: $TOKEN"
echo ""

# 5. Check token contract
echo "5. Token Contract Check:"
TOKEN_CODE=$(cast code $TOKEN --rpc-url $RPC_URL 2>&1)
if [[ "$TOKEN_CODE" == "0x" ]]; then
    echo "   ❌ ERROR: Token has no code at $TOKEN"
    echo "   The token contract was not deployed!"
    exit 1
else
    echo "   ✅ Token exists (${#TOKEN_CODE} bytes)"
fi
echo ""

# 6. Try different balance call methods
echo "6. Balance Call Attempts:"

# Method 1: Standard call
echo "   Method 1 (standard):"
BAL1=$(cast call $TOKEN "balanceOf(address)" $FAN1 --rpc-url $RPC_URL 2>&1)
echo "   Result: $BAL1"

# Method 2: With return type
echo "   Method 2 (with return type):"
BAL2=$(cast call $TOKEN "balanceOf(address)(uint256)" $FAN1 --rpc-url $RPC_URL 2>&1)
echo "   Result: $BAL2"

# Method 3: Using selector
echo "   Method 3 (using selector):"
FAN1_PADDED=$(cast --to-bytes32 $FAN1)
BAL3=$(cast call $TOKEN "0x70a08231${FAN1_PADDED:2}" --rpc-url $RPC_URL 2>&1)
echo "   Result: $BAL3"

echo ""

# 7. Check vault state
echo "7. Vault State:"
TOTAL_SUPPLY=$(cast call $VAULT "totalSupply()" --rpc-url $RPC_URL 2>&1)
echo "   Total supply: $TOTAL_SUPPLY"

STAGE=$(cast call $VAULT "stage()" --rpc-url $RPC_URL 2>&1)
echo "   Stage: $STAGE"

AURA=$(cast call $VAULT "getCurrentAura()" --rpc-url $RPC_URL 2>&1)
echo "   Aura: $AURA"

echo ""
echo "=== Diagnostic Complete ==="