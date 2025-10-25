// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {CreatorVault} from "../contracts/CreatorVault.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

/**
 * @title OracleVaultIntegrationTest
 * @notice Integration tests for oracle-vault interaction
 * @dev Tests oracle updates AuraOracle, vault reads new value immediately
 *      Tests multiple vaults reading from same AuraOracle
 *      Tests vault operations (mint/redeem) use latest oracle aura
 *      Tests forced burn trigger after oracle aura drop
 *      Tests that vault never stores stale aura values
 *      Requirements: 5.1, 5.6, 8.4, 8.5
 */
contract OracleVaultIntegrationTest is Test {
    VaultFactory public factory;
    Treasury public treasury;
    AuraOracle public oracle;
    CreatorVault public vault1;
    CreatorVault public vault2;
    CreatorToken public token1;
    CreatorToken public token2;

    address public owner = address(1);
    address public oracleAddress = address(2);
    address public creator1 = address(3);
    address public creator2 = address(4);
    address public fan1 = address(5);
    address public fan2 = address(6);

    // Events
    event AuraUpdated(address indexed vault, uint256 aura, string ipfsHash, uint256 timestamp);
    event Minted(
        address indexed vault, address indexed minter, uint256 qty, uint256 collateral, uint8 stage, uint256 peg
    );
    event SupplyCapShrink(
        address indexed vault, uint256 oldCap, uint256 newCap, uint256 pendingBurn, uint256 graceEndTs
    );

    function setUp() public {
        // Deploy Treasury
        vm.prank(owner);
        treasury = new Treasury(owner);

        // Deploy AuraOracle
        vm.prank(owner);
        oracle = new AuraOracle(owner, oracleAddress);

        // Deploy VaultFactory
        vm.prank(owner);
        factory = new VaultFactory(owner, address(treasury), address(oracle));

        // Create vault1 for creator1
        (address vaultAddr1, address tokenAddr1) = factory.createVault("Creator1 Token", "CRT1", creator1, 100e18);
        vault1 = CreatorVault(vaultAddr1);
        token1 = CreatorToken(tokenAddr1);

        // Create vault2 for creator2
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Creator2 Token", "CRT2", creator2, 200e18);
        vault2 = CreatorVault(vaultAddr2);
        token2 = CreatorToken(tokenAddr2);

        // Fund accounts
        vm.deal(creator1, 10_000e18);
        vm.deal(creator2, 10_000e18);
        vm.deal(fan1, 10_000e18);
        vm.deal(fan2, 10_000e18);

        // Bootstrap both vaults
        vm.prank(creator1);
        vault1.bootstrapCreatorStake{value: 100e18}();

        vm.prank(creator2);
        vault2.bootstrapCreatorStake{value: 100e18}();
    }

    // ============ Helper Functions ============

    function calculateRequiredCollateral(uint256 qty, uint256 peg) internal pure returns (uint256) {
        uint256 WAD = 1e18;
        uint256 MIN_CR = 1.5e18;
        return (qty * peg * MIN_CR) / (WAD * WAD);
    }

    function calculateMintFee(uint256 requiredCollateral) internal pure returns (uint256) {
        uint256 WAD = 1e18;
        uint256 MINT_FEE = 0.005e18;
        return (requiredCollateral * MINT_FEE) / WAD;
    }

    // ============ Test: Oracle updates AuraOracle, vault reads new value immediately ============

    /**
     * @notice Test oracle updates AuraOracle, vault reads new value immediately
     * @dev Requirements: 5.1, 5.6, 8.4
     */
    function test_OracleUpdate_VaultReadsImmediately() public {
        // Initial state: no aura set yet
        assertEq(vault1.getCurrentAura(), 0, "Initial aura should be 0");

        // Oracle pushes aura to AuraOracle
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmInitialAura");

        // Vault should read new value immediately
        assertEq(vault1.getCurrentAura(), 100, "Vault should read aura immediately after oracle update");
        assertEq(vault1.getPeg(), 1e18, "Peg should be calculated from new aura");

        // Wait for cooldown and update again
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 150, "QmUpdatedAura");

        // Vault should read updated value immediately
        assertEq(vault1.getCurrentAura(), 150, "Vault should read updated aura immediately");
        assertEq(vault1.getPeg(), 1.25e18, "Peg should update based on new aura");
    }

    /**
     * @notice Test vault never stores aura, always reads from oracle
     * @dev Requirements: 5.1, 8.4
     */
    function test_VaultNeverStoresAura() public {
        // Set initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        uint256 aura1 = vault1.getCurrentAura();
        assertEq(aura1, 100, "First read should be 100");

        // Update aura in oracle
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 120, "QmAura120");

        // Vault should immediately reflect new value (no stale data)
        uint256 aura2 = vault1.getCurrentAura();
        assertEq(aura2, 120, "Second read should be 120 (no stale data)");

        // Multiple reads should all return same current value
        assertEq(vault1.getCurrentAura(), 120, "Third read should still be 120");
        assertEq(vault1.getCurrentAura(), 120, "Fourth read should still be 120");
    }

    // ============ Test: Multiple vaults reading from same AuraOracle ============

    /**
     * @notice Test multiple vaults reading from same AuraOracle
     * @dev Requirements: 5.1, 5.6, 8.4
     */
    function test_MultipleVaults_SameOracle() public {
        // Set different aura values for each vault
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 80, "QmVault1Aura");

        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 150, "QmVault2Aura");

        // Each vault should read its own aura value
        assertEq(vault1.getCurrentAura(), 80, "Vault1 should read 80");
        assertEq(vault2.getCurrentAura(), 150, "Vault2 should read 150");

        // Pegs should be calculated independently
        assertEq(vault1.getPeg(), 0.9e18, "Vault1 peg should be 0.9");
        assertEq(vault2.getPeg(), 1.25e18, "Vault2 peg should be 1.25");

        // Update vault1 aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 120, "QmVault1Updated");

        // Vault1 should reflect new value, vault2 unchanged
        assertEq(vault1.getCurrentAura(), 120, "Vault1 should read updated value");
        assertEq(vault2.getCurrentAura(), 150, "Vault2 should remain unchanged");
    }

    /**
     * @notice Test multiple vaults with independent cooldowns
     * @dev Requirements: 5.1, 5.2, 5.6
     */
    function test_MultipleVaults_IndependentCooldowns() public {
        // Set initial aura for vault1
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmVault1Initial");

        // Wait 3 hours
        vm.warp(block.timestamp + 3 hours);

        // Set initial aura for vault2 (3 hours after vault1)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 100, "QmVault2Initial");

        // Wait another 3 hours (total 6 hours from vault1 initial, 3 hours from vault2 initial)
        vm.warp(block.timestamp + 3 hours);

        // Update vault1 (should succeed - 6 hours elapsed)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 110, "QmVault1Update");

        // Vault1 should read new value
        assertEq(vault1.getCurrentAura(), 110, "Vault1 should be updated");

        // Try to update vault2 (should fail - only 3 hours elapsed)
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.CooldownNotElapsed.selector);
        oracle.pushAura(address(vault2), 110, "QmVault2Update");

        // Vault2 should still have old value
        assertEq(vault2.getCurrentAura(), 100, "Vault2 should not be updated");
    }

    // ============ Test: Vault operations use latest oracle aura ============

    /**
     * @notice Test mint uses latest oracle aura for peg calculation
     * @dev Requirements: 5.1, 5.2, 5.3, 8.4
     */
    function test_Mint_UsesLatestOracleAura() public {
        // Set initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        // Mint at peg = 1.0
        uint256 qty1 = 10e18;
        uint256 peg1 = vault1.getPeg();
        assertEq(peg1, 1e18, "Initial peg should be 1.0");

        uint256 collateral1 = calculateRequiredCollateral(qty1, peg1);
        uint256 fee1 = calculateMintFee(collateral1);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral1 + fee1}(qty1);

        assertEq(token1.balanceOf(fan1), qty1, "Fan1 should have tokens");

        // Update aura in oracle
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 150, "QmAura150");

        // Mint again - should use new peg = 1.25
        uint256 qty2 = 10e18;
        uint256 peg2 = vault1.getPeg();
        assertEq(peg2, 1.25e18, "Updated peg should be 1.25");

        uint256 collateral2 = calculateRequiredCollateral(qty2, peg2);
        uint256 fee2 = calculateMintFee(collateral2);

        // Verify higher peg requires more collateral
        assertGt(collateral2, collateral1, "Higher peg should require more collateral");

        vm.prank(fan2);
        vault1.mintTokens{value: collateral2 + fee2}(qty2);

        assertEq(token1.balanceOf(fan2), qty2, "Fan2 should have tokens");
    }

    /**
     * @notice Test redeem uses latest oracle aura for health check
     * @dev Requirements: 5.1, 5.2, 8.4
     */
    function test_Redeem_UsesLatestOracleAura() public {
        // Set initial aura and mint tokens
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        uint256 qty = 50e18;
        uint256 peg = vault1.getPeg();
        uint256 collateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(collateral);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral + fee}(qty);

        // Update aura to increase peg
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 150, "QmAura150");

        // Verify new peg is higher
        uint256 newPeg = vault1.getPeg();
        assertEq(newPeg, 1.25e18, "New peg should be 1.25");

        // Redeem tokens - health check should use current peg
        uint256 redeemQty = 25e18;

        vm.prank(fan1);
        token1.approve(address(vault1), redeemQty);

        vm.prank(fan1);
        vault1.redeemTokens(redeemQty);

        // Verify redemption succeeded
        assertEq(token1.balanceOf(fan1), qty - redeemQty, "Fan should have remaining tokens");
    }

    /**
     * @notice Test supply cap check uses latest oracle aura
     * @dev Requirements: 5.3, 5.4, 8.5
     */
    function test_Mint_SupplyCapUsesLatestAura() public {
        // Set high aura (high supply cap)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 200, "QmHighAura");

        // Supply cap at aura=200: 100 * 1.75 = 175
        uint256 highCap = vault1.getCurrentSupplyCap();
        assertEq(highCap, 175e18, "High supply cap should be 175");

        // Mint 150 tokens (below cap)
        uint256 qty1 = 150e18;
        uint256 peg1 = vault1.getPeg();
        uint256 collateral1 = calculateRequiredCollateral(qty1, peg1);
        uint256 fee1 = calculateMintFee(collateral1);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral1 + fee1}(qty1);

        assertEq(vault1.totalSupply(), 150e18, "Supply should be 150");

        // Drop aura (supply cap shrinks)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 50, "QmLowAura");

        // New supply cap: 100 * 0.625 = 62.5
        uint256 lowCap = vault1.getCurrentSupplyCap();
        assertEq(lowCap, 62.5e18, "Low supply cap should be 62.5");

        // Try to mint more (should fail - supply would exceed cap)
        uint256 qty2 = 10e18;
        uint256 peg2 = vault1.getPeg();
        uint256 collateral2 = calculateRequiredCollateral(qty2, peg2);
        uint256 fee2 = calculateMintFee(collateral2);

        vm.prank(fan2);
        vm.expectRevert(CreatorVault.ExceedsSupplyCap.selector);
        vault1.mintTokens{value: collateral2 + fee2}(qty2);
    }

    // ============ Test: Forced burn trigger after oracle aura drop ============

    /**
     * @notice Test forced burn trigger after oracle aura drop
     * @dev Requirements: 5.1, 5.6, 6.1, 8.5
     */
    function test_ForcedBurn_TriggeredByOracleAuraDrop() public {
        // Set high aura and mint tokens
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 200, "QmHighAura");

        uint256 qty = 150e18;
        uint256 peg = vault1.getPeg();
        uint256 collateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(collateral);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral + fee}(qty);

        assertEq(vault1.totalSupply(), 150e18, "Supply should be 150");

        // Drop aura in oracle
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 0, "QmLowAura");

        // New supply cap: 100 * 0.25 = 25
        uint256 newCap = vault1.getCurrentSupplyCap();
        assertEq(newCap, 25e18, "New supply cap should be 25");

        // Supply (150) > cap (25), forced burn should trigger
        uint256 expectedBurn = 150e18 - 25e18; // 125 tokens

        vm.expectEmit(true, false, false, true);
        emit SupplyCapShrink(address(vault1), 150e18, 25e18, expectedBurn, block.timestamp + 24 hours);

        vault1.checkAndTriggerForcedBurn();

        // Verify forced burn state
        assertEq(vault1.pendingForcedBurn(), expectedBurn, "Pending burn should be 125");
        assertEq(vault1.forcedBurnDeadline(), block.timestamp + 24 hours, "Deadline should be set");
    }

    /**
     * @notice Test forced burn not triggered when supply below cap
     * @dev Requirements: 6.1, 8.5
     */
    function test_ForcedBurn_NotTriggeredWhenSupplyBelowCap() public {
        // Set aura and mint tokens
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        uint256 qty = 50e18;
        uint256 peg = vault1.getPeg();
        uint256 collateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(collateral);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral + fee}(qty);

        // Supply cap at aura=100: 100 tokens
        // Supply: 50 tokens (below cap)

        // Drop aura slightly
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 80, "QmAura80");

        // New supply cap: 100 * 0.85 = 85 tokens
        // Supply: 50 tokens (still below cap)

        vault1.checkAndTriggerForcedBurn();

        // Verify no forced burn triggered
        assertEq(vault1.pendingForcedBurn(), 0, "No pending burn should be set");
        assertEq(vault1.forcedBurnDeadline(), 0, "No deadline should be set");
    }

    /**
     * @notice Test multiple oracle updates and forced burn trigger
     * @dev Requirements: 5.1, 5.6, 6.1, 8.5
     */
    function test_ForcedBurn_MultipleOracleUpdates() public {
        // Phase 1: High aura, mint tokens
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 200, "QmPhase1");

        uint256 qty = 150e18;
        uint256 peg = vault1.getPeg();
        uint256 collateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(collateral);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral + fee}(qty);

        // Phase 2: Moderate drop (supply still below cap)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 150, "QmPhase2");

        // Supply cap: 100 * 1.375 = 137.5 (supply 150 > cap, should trigger)
        vault1.checkAndTriggerForcedBurn();
        assertGt(vault1.pendingForcedBurn(), 0, "Forced burn should be triggered");

        // Phase 3: Aura recovers (but forced burn still pending)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 180, "QmPhase3");

        // Supply cap now higher, but forced burn already triggered
        assertGt(vault1.pendingForcedBurn(), 0, "Forced burn should still be pending");
    }

    // ============ Test: Vault never stores stale aura values ============

    /**
     * @notice Test vault always reads fresh aura from oracle
     * @dev Requirements: 5.1, 8.4
     */
    function test_VaultAlwaysReadsFreshAura() public {
        // Set initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        // Read aura multiple times
        assertEq(vault1.getCurrentAura(), 100, "Read 1 should be 100");
        assertEq(vault1.getCurrentAura(), 100, "Read 2 should be 100");

        // Update aura in oracle
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 120, "QmAura120");

        // Immediately read new value (no stale data)
        assertEq(vault1.getCurrentAura(), 120, "Read 3 should be 120 immediately");
        assertEq(vault1.getCurrentAura(), 120, "Read 4 should be 120");

        // Update again
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 80, "QmAura80");

        // Immediately read new value
        assertEq(vault1.getCurrentAura(), 80, "Read 5 should be 80 immediately");
    }

    /**
     * @notice Test peg calculation always uses fresh aura
     * @dev Requirements: 5.1, 5.2, 8.4
     */
    function test_PegAlwaysUsesFreshAura() public {
        // Set initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        assertEq(vault1.getPeg(), 1e18, "Peg 1 should be 1.0");

        // Update aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 150, "QmAura150");

        // Peg should immediately reflect new aura
        assertEq(vault1.getPeg(), 1.25e18, "Peg 2 should be 1.25 immediately");

        // Update aura again
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 50, "QmAura50");

        // Peg should immediately reflect new aura
        assertEq(vault1.getPeg(), 0.75e18, "Peg 3 should be 0.75 immediately");
    }

    /**
     * @notice Test supply cap calculation always uses fresh aura
     * @dev Requirements: 5.3, 5.4, 8.5
     */
    function test_SupplyCapAlwaysUsesFreshAura() public {
        // Set initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmAura100");

        assertEq(vault1.getCurrentSupplyCap(), 100e18, "Cap 1 should be 100");

        // Update aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 200, "QmAura200");

        // Supply cap should immediately reflect new aura
        assertEq(vault1.getCurrentSupplyCap(), 175e18, "Cap 2 should be 175 immediately");

        // Update aura again
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 0, "QmAura0");

        // Supply cap should immediately reflect new aura
        assertEq(vault1.getCurrentSupplyCap(), 25e18, "Cap 3 should be 25 immediately");
    }

    /**
     * @notice Test complete integration: oracle updates, vault operations, forced burn
     * @dev Requirements: 5.1, 5.2, 5.3, 5.6, 6.1, 8.4, 8.5
     */
    function test_FullIntegration_OracleVaultInteraction() public {
        // Phase 1: Initialize with high aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 200, "QmPhase1");

        assertEq(vault1.getCurrentAura(), 200, "Phase 1: Aura should be 200");
        assertEq(vault1.getPeg(), 1.5e18, "Phase 1: Peg should be 1.5");
        assertEq(vault1.getCurrentSupplyCap(), 175e18, "Phase 1: Cap should be 175");

        // Phase 2: Mint tokens at high peg
        uint256 qty1 = 150e18;
        uint256 peg1 = vault1.getPeg();
        uint256 collateral1 = calculateRequiredCollateral(qty1, peg1);
        uint256 fee1 = calculateMintFee(collateral1);

        vm.prank(fan1);
        vault1.mintTokens{value: collateral1 + fee1}(qty1);

        assertEq(vault1.totalSupply(), 150e18, "Phase 2: Supply should be 150");

        // Phase 3: Oracle drops aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 50, "QmPhase3");

        assertEq(vault1.getCurrentAura(), 50, "Phase 3: Aura should be 50");
        assertEq(vault1.getPeg(), 0.75e18, "Phase 3: Peg should be 0.75");
        assertEq(vault1.getCurrentSupplyCap(), 62.5e18, "Phase 3: Cap should be 62.5");

        // Phase 4: Forced burn triggered
        vault1.checkAndTriggerForcedBurn();

        uint256 expectedBurn = 150e18 - 62.5e18; // 87.5 tokens
        assertEq(vault1.pendingForcedBurn(), expectedBurn, "Phase 4: Pending burn should be 87.5");

        // Phase 5: Try to mint (should fail due to supply cap)
        uint256 qty2 = 10e18;
        uint256 peg2 = vault1.getPeg();
        uint256 collateral2 = calculateRequiredCollateral(qty2, peg2);
        uint256 fee2 = calculateMintFee(collateral2);

        vm.prank(fan2);
        vm.expectRevert(CreatorVault.ExceedsSupplyCap.selector);
        vault1.mintTokens{value: collateral2 + fee2}(qty2);

        // Phase 6: Oracle updates aura again
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault1), 100, "QmPhase6");

        // Vault immediately reflects new aura
        assertEq(vault1.getCurrentAura(), 100, "Phase 6: Aura should be 100");
        assertEq(vault1.getPeg(), 1e18, "Phase 6: Peg should be 1.0");
        assertEq(vault1.getCurrentSupplyCap(), 100e18, "Phase 6: Cap should be 100");

        // Forced burn still pending (deadline not reached)
        assertEq(vault1.pendingForcedBurn(), expectedBurn, "Phase 6: Forced burn still pending");
    }
}
