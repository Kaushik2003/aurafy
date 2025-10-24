#!/usr/bin/env node

/**
 * Test script for oracle functions
 */

require('dotenv').config({ path: require('path').join(__dirname, '.env.local') });

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

const {
    fetchFarcasterMetrics,
    computeAura,
    clamp,
    normalizeLog
} = require('./oracle.js');

/**
 * Fetch data from AuraOracle contract by vault address
 * Tests reading data back from the contract using getAura and getIpfsHash
 * @param {string} vaultAddress - Vault address to query (optional, defaults to test address)
 * @returns {Object} Object containing aura score and IPFS hash
 */
async function fetchData(vaultAddress) {
    const RPC_URL = process.env.RPC_URL || 'https://alfajores-forno.celo-testnet.org';
    const ORACLE_CONTRACT_ADDRESS = process.env.ORACLE_CONTRACT_ADDRESS;

    if (!ORACLE_CONTRACT_ADDRESS) {
        throw new Error('ORACLE_CONTRACT_ADDRESS environment variable not set');
    }

    // Use provided vault address or default test address
    const queryAddress = vaultAddress || '0x0000000000000000000000000000000000000001';

    console.log(`\n🔍 Fetching data from AuraOracle...`);
    console.log(`🔗 RPC: ${RPC_URL}`);
    console.log(`📝 Oracle Contract: ${ORACLE_CONTRACT_ADDRESS}`);
    console.log(`🏦 Vault Address: ${queryAddress}`);

    // Connect to network (read-only, no wallet needed)
    const provider = new ethers.JsonRpcProvider(RPC_URL);

    // Load AuraOracle ABI
    const oracleAbiPath = path.join(__dirname, '../out/AuraOracle.sol/AuraOracle.json');

    if (!fs.existsSync(oracleAbiPath)) {
        throw new Error('AuraOracle ABI not found. Run `forge build` first.');
    }

    const oracleArtifact = JSON.parse(fs.readFileSync(oracleAbiPath, 'utf8'));
    const oracleContract = new ethers.Contract(ORACLE_CONTRACT_ADDRESS, oracleArtifact.abi, provider);

    // Call getAura
    const aura = await oracleContract.getAura(queryAddress);
    console.log(`📊 Aura Score: ${aura.toString()}`);

    // Call getIpfsHash
    const ipfsHash = await oracleContract.getIpfsHash(queryAddress);
    console.log(`🔗 IPFS Hash: ${ipfsHash || '(empty)'}`);

    // Call getLastUpdateTimestamp
    const lastUpdate = await oracleContract.getLastUpdateTimestamp(queryAddress);
    const lastUpdateDate = lastUpdate > 0 ? new Date(Number(lastUpdate) * 1000).toISOString() : 'Never';
    console.log(`⏰ Last Update: ${lastUpdateDate}`);

    return {
        vaultAddress: queryAddress,
        aura: aura.toString(),
        ipfsHash,
        lastUpdate: lastUpdate.toString(),
        lastUpdateDate
    };
}

console.log('🧪 Testing AuraFi Oracle Functions\n');

// Test 1: Clamp function
console.log('Test 1: Clamp function');
console.assert(clamp(50, 0, 100) === 50, 'Clamp mid-range failed');
console.assert(clamp(-10, 0, 100) === 0, 'Clamp below min failed');
console.assert(clamp(150, 0, 100) === 100, 'Clamp above max failed');
console.log('✅ Clamp tests passed\n');

// Test 2: Normalize function
console.log('Test 2: Normalize function');
const norm1 = normalizeLog(100, 10, 10000, 200);
console.log(`  normalizeLog(100, 10, 10000, 200) = ${norm1.toFixed(2)}`);
console.assert(norm1 >= 0 && norm1 <= 200, 'Normalize out of range');

const norm2 = normalizeLog(5, 10, 10000, 200);
console.log(`  normalizeLog(5, 10, 10000, 200) = ${norm2.toFixed(2)} (should be 0)`);
console.assert(norm2 === 0, 'Normalize below min failed');

const norm3 = normalizeLog(20000, 10, 10000, 200);
console.log(`  normalizeLog(20000, 10, 10000, 200) = ${norm3.toFixed(2)} (should be 200)`);
console.assert(norm3 === 200, 'Normalize above max failed');
console.log('✅ Normalize tests passed\n');

// Test 3: Fetch metrics (mock mode)
console.log('Test 3: Fetch metrics (mock mode)');
fetchFarcasterMetrics('12345', true).then(metrics => {
    console.log('  Mock metrics:', JSON.stringify(metrics, null, 2));
    console.assert(metrics.fid === '12345', 'FID mismatch');
    console.assert(metrics.followerCount > 0, 'Invalid follower count');
    console.log('✅ Fetch metrics test passed\n');

    // Test 4: Compute aura
    console.log('Test 4: Compute aura');
    const aura = computeAura(metrics);
    console.assert(aura >= 0 && aura <= 200, 'Aura out of range');
    console.log(`✅ Aura computed: ${aura}\n`);

    // Test 5: Different metric scenarios
    console.log('Test 5: Different metric scenarios');

    const lowMetrics = {
        fid: 'test',
        followerCount: 50,
        followerDelta: 5,
        avgLikes: 2,
        isVerified: false,
        timestamp: Date.now()
    };
    const lowAura = computeAura(lowMetrics);
    console.log(`  Low metrics → Aura: ${lowAura}`);

    const highMetrics = {
        fid: 'test',
        followerCount: 50000,
        followerDelta: 500,
        avgLikes: 200,
        isVerified: true,
        timestamp: Date.now()
    };
    const highAura = computeAura(highMetrics);
    console.log(`  High metrics → Aura: ${highAura}`);

    const spamMetrics = {
        fid: 'test',
        followerCount: 100000,
        followerDelta: 0,
        avgLikes: 2,
        isVerified: false,
        timestamp: Date.now()
    };
    const spamAura = computeAura(spamMetrics);
    console.log(`  Spam-like metrics → Aura: ${spamAura} (should be penalized)`);

    console.assert(highAura > lowAura, 'High metrics should yield higher aura');
    console.log('✅ Scenario tests passed\n');

    console.log('🎉 All tests passed!');

    // Test 6: Fetch data from contract
    // Check if vault address provided as command-line argument
    const vaultAddress = process.argv[2];
    
    console.log('\nTest 6: Fetch data from AuraOracle contract');
    if (vaultAddress) {
        console.log(`📍 Using provided vault address: ${vaultAddress}`);
    } else {
        console.log('📍 No vault address provided, using default test address');
    }
    
    return fetchData(vaultAddress).then(data => {
        console.log('\n✅ Successfully fetched data from contract:');
        console.log(JSON.stringify(data, null, 2));
        console.log('\n🎉 All tests including contract read passed!');
        
        if (!vaultAddress) {
            console.log('\n💡 To query a specific vault address:');
            console.log('   node test-oracle.js <vault-address>');
            console.log('   Example: node test-oracle.js 0x1234567890123456789012345678901234567890');
        }
    });
}).catch(error => {
    console.error('❌ Test failed:', error);
    process.exit(1);
});
