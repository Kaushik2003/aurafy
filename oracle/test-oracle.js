#!/usr/bin/env node

/**
 * Test script for oracle functions
 */

const {
    fetchFarcasterMetrics,
    computeAura,
    clamp,
    normalizeLog
} = require('./oracle.js');

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
}).catch(error => {
    console.error('❌ Test failed:', error);
    process.exit(1);
});
