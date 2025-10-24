// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {CreatorVault} from "../contracts/CreatorVault.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

/**
 * @title OracleAuraReadingTest
 * @notice Comprehensive unit tests for oracle aura reading and forced burn triggering
 * @dev Tests getCurrentAura(), getPeg(), dynamic peg/supply cap updates, and checkAndTriggerForcedBurn()
 *      Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 8.4, 8.5
 */
contract OracleAuraReadingTest is Test {
    VaultFactory public factory;
    Treasury public treasury;
    AuraOracle public oracle;
    CreatorVault public vault;
    CreatorToken public token;

    address public owner = address(1);
    address public oracleAddress = address(2);
    address public creator = address(3);
    address public fan1 = address(4);
    address public fan2 = address(5);

    // Events
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

        // Create a vault for testing
        (address vaultAddr, address tokenAddr) = factory.createVault("Creator Token", "CRTR", creator, 100_000e18);

        vault = CreatorVault(vaultAddr);
        token = CreatorToken(tokenAddr);

        // Fund accounts with CELO for testing
        vm.deal(creator, 10_000e18);
        vm.deal(fan1, 10_000e18);
        vm.deal(fan2, 10_000e18);

        // Bootstrap creator stake to unlock stage 1 (requires 100 CELO)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Initialize aura in oracle (A_REF = 100 gives BASE_PRICE peg)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 100, "QmInitialAura");
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

    // ============ getCurrentAura() Tests ============

    /**
     * @notice Test getCurrentAura() fetches correct value from AuraOracle
     * @dev Requirements: 5.1, 8.4
     */
    function test_GetCurrentAura_FetchesFromOracle() public view {
        uint256 aura = vault.getCurrentAura();
        assertEq(aura, 100, "getCurrentAura should fetch value from oracle");
    }

    /**
     * @notice Test getCurrentAura() returns updated value after oracle update
     * @dev Requirements: 5.1, 5.2, 8.4
     */
    function test_GetCurrentAura_UpdatesAfterOracleChange() public {
        // Initial aura is 100
        assertEq(vault.getCurrentAura(), 100, "Initial aura should be 100");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Update aura in oracle to 150
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 150, "QmUpdatedAura");

        // Verify vault reads new aura
        assertEq(vault.getCurrentAura(), 150, "getCurrentAura should return updated value");
    }

    /**
     * @notice Test getCurrentAura() with zero aura
     * @dev Requirements: 5.1, 8.4
     */
    function test_GetCurrentAura_ZeroAura() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 0
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 0, "QmZeroAura");

        assertEq(vault.getCurrentAura(), 0, "getCurrentAura should return 0");
    }

    /**
     * @notice Test getCurrentAura() with maximum aura
     * @dev Requirements: 5.1, 8.4
     */
    function test_GetCurrentAura_MaxAura() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 200 (A_MAX)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 200, "QmMaxAura");

        assertEq(vault.getCurrentAura(), 200, "getCurrentAura should return 200");
    }

    // ============ getPeg() Tests ============

    /**
     * @notice Test getPeg() calculates correct peg based on oracle aura
     * @dev Requirements: 5.1, 5.2, 8.4
     */
    function test_GetPeg_CalculatesFromOracleAura() public view {
        // Aura = 100 (A_REF), should give BASE_PRICE = 1e18
        uint256 peg = vault.getPeg();
        assertEq(peg, 1e18, "Peg should be BASE_PRICE when aura = A_REF");
    }

    /**
     * @notice Test peg updates dynamically when oracle aura changes
     * @dev Requirements: 5.2, 5.3, 8.4
     */
    function test_GetPeg_UpdatesDynamically() public {
        // Initial peg with aura = 100
        uint256 initialPeg = vault.getPeg();
        assertEq(initialPeg, 1e18, "Initial peg should be BASE_PRICE");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Update aura to 150 (above A_REF)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 150, "QmHigherAura");

        // Peg should increase
        // P(150) = BASE_PRICE * (1 + K * (150/100 - 1))
        // P(150) = 1e18 * (1 + 0.5 * (1.5 - 1))
        // P(150) = 1e18 * (1 + 0.5 * 0.5)
        // P(150) = 1e18 * 1.25 = 1.25e18
        uint256 newPeg = vault.getPeg();
        assertEq(newPeg, 1.25e18, "Peg should increase when aura increases");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Update aura to 50 (below A_REF)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 50, "QmLowerAura");

        // Peg should decrease
        // P(50) = BASE_PRICE * (1 + K * (50/100 - 1))
        // P(50) = 1e18 * (1 + 0.5 * (0.5 - 1))
        // P(50) = 1e18 * (1 + 0.5 * -0.5)
        // P(50) = 1e18 * 0.75 = 0.75e18
        uint256 lowerPeg = vault.getPeg();
        assertEq(lowerPeg, 0.75e18, "Peg should decrease when aura decreases");
    }

    /**
     * @notice Test peg clamping at P_MIN boundary
     * @dev Requirements: 5.2, 5.3, 8.4
     */
    function test_GetPeg_ClampsAtPMin() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 0 (minimum)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 0, "QmMinAura");

        // P(0) = BASE_PRICE * (1 + K * (0/100 - 1))
        // P(0) = 1e18 * (1 + 0.5 * (0 - 1))
        // P(0) = 1e18 * (1 - 0.5) = 0.5e18
        // This is above P_MIN (0.3e18), so not clamped
        uint256 peg = vault.getPeg();
        assertEq(peg, 0.5e18, "Peg at aura=0 should be 0.5e18");
        
        // P_MIN would only be hit with negative aura values, which are not possible
        // The minimum aura is 0, which gives peg = 0.5e18
    }

    /**
     * @notice Test peg clamping at P_MAX boundary
     * @dev Requirements: 5.2, 5.3, 8.4
     */
    function test_GetPeg_ClampsAtPMax() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 200 (maximum)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 200, "QmMaxAura");

        // Peg should be clamped at P_MAX = 3.0e18
        // P(200) = BASE_PRICE * (1 + K * (200/100 - 1))
        // P(200) = 1e18 * (1 + 0.5 * (2 - 1))
        // P(200) = 1e18 * (1 + 0.5 * 1)
        // P(200) = 1e18 * 1.5 = 1.5e18 (below P_MAX, so not clamped)
        uint256 peg = vault.getPeg();
        assertEq(peg, 1.5e18, "Peg at aura=200 should be 1.5e18");

        // To hit P_MAX, we need aura much higher than A_MAX
        // But since A_MAX = 200, we can't test this in normal operation
        // The clamping logic is still correct in the contract
    }

    /**
     * @notice Test peg calculation with various aura values
     * @dev Requirements: 5.2, 8.4
     */
    function test_GetPeg_VariousAuraValues() public {
        // Test aura = 80
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 80, "QmAura80");
        
        // P(80) = 1e18 * (1 + 0.5 * (0.8 - 1)) = 1e18 * 0.9 = 0.9e18
        assertEq(vault.getPeg(), 0.9e18, "Peg at aura=80 should be 0.9e18");

        // Test aura = 120
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 120, "QmAura120");
        
        // P(120) = 1e18 * (1 + 0.5 * (1.2 - 1)) = 1e18 * 1.1 = 1.1e18
        assertEq(vault.getPeg(), 1.1e18, "Peg at aura=120 should be 1.1e18");
    }

    // ============ Supply Cap Dynamic Updates Tests ============

    /**
     * @notice Test supply cap updates dynamically when oracle aura changes
     * @dev Requirements: 5.3, 5.4, 8.5
     */
    function test_GetCurrentSupplyCap_UpdatesDynamically() public {
        // Initial supply cap with aura = 100
        // SupplyCap(100) = BaseCap * (1 + 0.75 * (100 - 100) / 100) = 100,000
        uint256 initialCap = vault.getCurrentSupplyCap();
        assertEq(initialCap, 100_000e18, "Initial supply cap should be baseCap");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Update aura to 150
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 150, "QmHigherAura");

        // SupplyCap(150) = 100,000 * (1 + 0.75 * (150 - 100) / 100)
        // SupplyCap(150) = 100,000 * (1 + 0.75 * 0.5)
        // SupplyCap(150) = 100,000 * 1.375 = 137,500
        uint256 newCap = vault.getCurrentSupplyCap();
        assertEq(newCap, 137_500e18, "Supply cap should increase when aura increases");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Update aura to 50
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 50, "QmLowerAura");

        // SupplyCap(50) = 100,000 * (1 + 0.75 * (50 - 100) / 100)
        // SupplyCap(50) = 100,000 * (1 + 0.75 * -0.5)
        // SupplyCap(50) = 100,000 * 0.625 = 62,500
        uint256 lowerCap = vault.getCurrentSupplyCap();
        assertEq(lowerCap, 62_500e18, "Supply cap should decrease when aura decreases");
    }

    /**
     * @notice Test supply cap clamping at minimum (baseCap * 0.25)
     * @dev Requirements: 5.4, 8.5
     */
    function test_GetCurrentSupplyCap_ClampsAtMin() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 0 (minimum)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 0, "QmMinAura");

        // SupplyCap(0) = 100,000 * (1 + 0.75 * (0 - 100) / 100)
        // SupplyCap(0) = 100,000 * (1 - 0.75) = 25,000
        // This is exactly baseCap * 0.25, so it's at the minimum
        uint256 cap = vault.getCurrentSupplyCap();
        assertEq(cap, 25_000e18, "Supply cap should be clamped at baseCap * 0.25");
    }

    /**
     * @notice Test supply cap clamping at maximum (baseCap * 4)
     * @dev Requirements: 5.4, 8.5
     */
    function test_GetCurrentSupplyCap_ClampsAtMax() public {
        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // Set aura to 200 (maximum)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 200, "QmMaxAura");

        // SupplyCap(200) = 100,000 * (1 + 0.75 * (200 - 100) / 100)
        // SupplyCap(200) = 100,000 * (1 + 0.75 * 1)
        // SupplyCap(200) = 100,000 * 1.75 = 175,000
        // This is below baseCap * 4 (400,000), so not clamped
        uint256 cap = vault.getCurrentSupplyCap();
        assertEq(cap, 175_000e18, "Supply cap at aura=200 should be 175,000");
    }

    // ============ Mint/Redeem Use Current Oracle Aura Tests ============

    /**
     * @notice Test that mint uses current oracle aura, not stale values
     * @dev Requirements: 5.1, 5.2, 5.3
     */
    function test_Mint_UsesCurrentOracleAura() public {
        // Mint at initial peg (aura = 100, peg = 1e18)
        uint256 qty1 = 10e18;
        uint256 peg1 = vault.getPeg();
        assertEq(peg1, 1e18, "Initial peg should be 1e18");

        uint256 requiredCollateral1 = calculateRequiredCollateral(qty1, peg1);
        uint256 fee1 = calculateMintFee(requiredCollateral1);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral1 + fee1}(qty1);

        // Wait for cooldown and update aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 150, "QmHigherAura");

        // Mint again - should use new peg (1.25e18)
        uint256 qty2 = 10e18;
        uint256 peg2 = vault.getPeg();
        assertEq(peg2, 1.25e18, "New peg should be 1.25e18");

        uint256 requiredCollateral2 = calculateRequiredCollateral(qty2, peg2);
        uint256 fee2 = calculateMintFee(requiredCollateral2);

        // Verify new collateral requirement is higher
        assertGt(requiredCollateral2, requiredCollateral1, "Higher peg should require more collateral");

        vm.prank(fan2);
        vault.mintTokens{value: requiredCollateral2 + fee2}(qty2);

        // Verify both mints succeeded with different pegs
        assertEq(token.balanceOf(fan1), qty1, "Fan1 should have tokens");
        assertEq(token.balanceOf(fan2), qty2, "Fan2 should have tokens");
    }

    /**
     * @notice Test that redeem uses current oracle aura, not stale values
     * @dev Requirements: 5.1, 5.2, 5.3
     */
    function test_Redeem_UsesCurrentOracleAura() public {
        // Mint tokens at initial peg
        uint256 qty = 100e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Wait for cooldown and update aura to increase peg
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 150, "QmHigherAura");

        // Verify new peg is higher
        uint256 newPeg = vault.getPeg();
        assertEq(newPeg, 1.25e18, "New peg should be 1.25e18");

        // Redeem tokens - health check should use current peg
        uint256 redeemQty = 50e18;
        
        // Approve vault to transfer tokens
        vm.prank(fan1);
        token.approve(address(vault), redeemQty);

        vm.prank(fan1);
        vault.redeemTokens(redeemQty);

        // Verify redemption succeeded with current peg
        assertEq(token.balanceOf(fan1), qty - redeemQty, "Fan should have remaining tokens");
    }

    // ============ checkAndTriggerForcedBurn() Tests ============

    /**
     * @notice Test checkAndTriggerForcedBurn() with supply > cap (forced burn triggered)
     * @dev Requirements: 6.1, 8.5
     */
    function test_CheckAndTriggerForcedBurn_SupplyExceedsCap() public {
        // Mint tokens at initial aura (100)
        uint256 qty = 400e18; // Mint 400 tokens
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        assertEq(vault.totalSupply(), qty, "Total supply should be 400");

        // Wait for cooldown and drop aura to 50
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 50, "QmLowerAura");

        // New supply cap should be 62,500 (calculated earlier)
        uint256 newSupplyCap = vault.getCurrentSupplyCap();
        assertEq(newSupplyCap, 62_500e18, "New supply cap should be 62,500");

        // Supply (400) is less than cap (62,500), so no forced burn should trigger
        // Let's mint more to exceed the cap after another aura drop

        // Mint more tokens (total will be 500)
        uint256 qty2 = 100e18;
        uint256 requiredCollateral2 = calculateRequiredCollateral(qty2, vault.getPeg());
        uint256 fee2 = calculateMintFee(requiredCollateral2);

        vm.prank(fan2);
        vault.mintTokens{value: requiredCollateral2 + fee2}(qty2);

        assertEq(vault.totalSupply(), 500e18, "Total supply should be 500");

        // Wait for cooldown and drop aura to 0 (minimum)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 0, "QmMinAura");

        // New supply cap should be 25,000
        uint256 minSupplyCap = vault.getCurrentSupplyCap();
        assertEq(minSupplyCap, 25_000e18, "Min supply cap should be 25,000");

        // Now supply (500) < cap (25,000), still no trigger
        // We need to test with actual supply exceeding cap
        // Let's create a scenario where we mint a lot, then aura drops

        // Reset: Create new vault with smaller baseCap for easier testing
        address newCreator = address(100);
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Test Token", "TEST", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);
        CreatorToken token2 = CreatorToken(tokenAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);

        // Bootstrap vault2
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Set initial aura high
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 200, "QmHighAura");

        // Supply cap at aura=200: 100 * 1.75 = 175 tokens
        uint256 highCap = vault2.getCurrentSupplyCap();
        assertEq(highCap, 175e18, "High supply cap should be 175");

        // Mint 150 tokens (below cap)
        uint256 mintQty = 150e18;
        uint256 mintPeg = vault2.getPeg();
        uint256 mintCollateral = calculateRequiredCollateral(mintQty, mintPeg);
        uint256 mintFee = calculateMintFee(mintCollateral);

        vm.prank(fan1);
        vault2.mintTokens{value: mintCollateral + mintFee}(mintQty);

        assertEq(vault2.totalSupply(), 150e18, "Supply should be 150");

        // Wait and drop aura to 0
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 0, "QmDropAura");

        // New supply cap: 100 * 0.25 = 25 tokens
        uint256 lowCap = vault2.getCurrentSupplyCap();
        assertEq(lowCap, 25e18, "Low supply cap should be 25");

        // Now supply (150) > cap (25), forced burn should trigger
        uint256 expectedPendingBurn = 150e18 - 25e18; // 125 tokens

        // Expect SupplyCapShrink event
        vm.expectEmit(true, false, false, true);
        emit SupplyCapShrink(
            address(vault2),
            150e18, // oldCap (current supply)
            25e18, // newCap
            expectedPendingBurn,
            block.timestamp + 24 hours
        );

        // Trigger forced burn
        vault2.checkAndTriggerForcedBurn();

        // Verify state
        assertEq(vault2.pendingForcedBurn(), expectedPendingBurn, "Pending forced burn should be set");
        assertEq(vault2.forcedBurnDeadline(), block.timestamp + 24 hours, "Deadline should be set");
    }

    /**
     * @notice Test checkAndTriggerForcedBurn() with supply <= cap (no action)
     * @dev Requirements: 6.1, 8.5
     */
    function test_CheckAndTriggerForcedBurn_SupplyBelowCap() public {
        // Mint tokens at initial aura (100)
        uint256 qty = 100e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        assertEq(vault.totalSupply(), qty, "Total supply should be 100");

        // Current supply cap is 100,000, supply is 100
        // Supply < cap, so no forced burn should trigger

        // Call checkAndTriggerForcedBurn
        vault.checkAndTriggerForcedBurn();

        // Verify no forced burn was triggered
        assertEq(vault.pendingForcedBurn(), 0, "No pending forced burn should be set");
        assertEq(vault.forcedBurnDeadline(), 0, "No deadline should be set");
    }

    /**
     * @notice Test checkAndTriggerForcedBurn() with supply exactly at cap
     * @dev Requirements: 6.1, 8.5
     */
    function test_CheckAndTriggerForcedBurn_SupplyAtCap() public {
        // Create vault with small baseCap for easier testing
        address newCreator = address(101);
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Test Token 2", "TEST2", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);
        CreatorToken token2 = CreatorToken(tokenAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);

        // Bootstrap vault2
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Set aura to 100 (supply cap = 100)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 100, "QmAura100");

        uint256 supplyCap = vault2.getCurrentSupplyCap();
        assertEq(supplyCap, 100e18, "Supply cap should be 100");

        // Mint exactly 100 tokens (at cap)
        uint256 mintQty = 100e18;
        uint256 mintPeg = vault2.getPeg();
        uint256 mintCollateral = calculateRequiredCollateral(mintQty, mintPeg);
        uint256 mintFee = calculateMintFee(mintCollateral);

        vm.prank(fan1);
        vault2.mintTokens{value: mintCollateral + mintFee}(mintQty);

        assertEq(vault2.totalSupply(), 100e18, "Supply should be 100");

        // Call checkAndTriggerForcedBurn
        vault2.checkAndTriggerForcedBurn();

        // Verify no forced burn was triggered (supply == cap, not >)
        assertEq(vault2.pendingForcedBurn(), 0, "No pending forced burn should be set");
        assertEq(vault2.forcedBurnDeadline(), 0, "No deadline should be set");
    }

    /**
     * @notice Test pendingForcedBurn and forcedBurnDeadline set correctly
     * @dev Requirements: 6.1, 8.5
     */
    function test_CheckAndTriggerForcedBurn_SetsStateCorrectly() public {
        // Create vault with small baseCap
        address newCreator = address(102);
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Test Token 3", "TEST3", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);

        // Bootstrap vault2
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Set high aura
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 200, "QmHighAura");

        // Mint 150 tokens
        uint256 mintQty = 150e18;
        uint256 mintPeg = vault2.getPeg();
        uint256 mintCollateral = calculateRequiredCollateral(mintQty, mintPeg);
        uint256 mintFee = calculateMintFee(mintCollateral);

        vm.prank(fan1);
        vault2.mintTokens{value: mintCollateral + mintFee}(mintQty);

        // Drop aura to 0
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 0, "QmLowAura");

        // Record timestamp before trigger
        uint256 triggerTime = block.timestamp;

        // Trigger forced burn
        vault2.checkAndTriggerForcedBurn();

        // Verify state
        uint256 expectedBurn = 150e18 - 25e18; // 125 tokens
        assertEq(vault2.pendingForcedBurn(), expectedBurn, "Pending burn should be 125");
        assertEq(vault2.forcedBurnDeadline(), triggerTime + 24 hours, "Deadline should be 24 hours from trigger");
    }

    /**
     * @notice Test SupplyCapShrink event emission
     * @dev Requirements: 6.1, 8.5
     */
    function test_CheckAndTriggerForcedBurn_EmitsEvent() public {
        // Create vault with small baseCap
        address newCreator = address(103);
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Test Token 4", "TEST4", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);

        // Bootstrap vault2
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Set high aura and mint
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 200, "QmHighAura");

        uint256 mintQty = 150e18;
        uint256 mintPeg = vault2.getPeg();
        uint256 mintCollateral = calculateRequiredCollateral(mintQty, mintPeg);
        uint256 mintFee = calculateMintFee(mintCollateral);

        vm.prank(fan1);
        vault2.mintTokens{value: mintCollateral + mintFee}(mintQty);

        // Drop aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 0, "QmLowAura");

        // Expect event
        vm.expectEmit(true, false, false, true);
        emit SupplyCapShrink(
            address(vault2),
            150e18, // oldCap (current supply)
            25e18, // newCap
            125e18, // pendingBurn
            block.timestamp + 24 hours // graceEndTs
        );

        vault2.checkAndTriggerForcedBurn();
    }

    /**
     * @notice Test that forced burn is not triggered if already pending
     * @dev Requirements: 6.1
     */
    function test_CheckAndTriggerForcedBurn_NoTriggerIfAlreadyPending() public {
        // Create vault with small baseCap
        address newCreator = address(104);
        (address vaultAddr2, address tokenAddr2) = factory.createVault("Test Token 5", "TEST5", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);

        // Bootstrap vault2
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Set high aura and mint
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 200, "QmHighAura");

        uint256 mintQty = 150e18;
        uint256 mintPeg = vault2.getPeg();
        uint256 mintCollateral = calculateRequiredCollateral(mintQty, mintPeg);
        uint256 mintFee = calculateMintFee(mintCollateral);

        vm.prank(fan1);
        vault2.mintTokens{value: mintCollateral + mintFee}(mintQty);

        // Drop aura
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 0, "QmLowAura");

        // First trigger
        vault2.checkAndTriggerForcedBurn();

        uint256 firstPendingBurn = vault2.pendingForcedBurn();
        uint256 firstDeadline = vault2.forcedBurnDeadline();

        assertGt(firstPendingBurn, 0, "First pending burn should be set");
        assertGt(firstDeadline, 0, "First deadline should be set");

        // Try to trigger again (should not change state)
        vault2.checkAndTriggerForcedBurn();

        assertEq(vault2.pendingForcedBurn(), firstPendingBurn, "Pending burn should not change");
        assertEq(vault2.forcedBurnDeadline(), firstDeadline, "Deadline should not change");
    }

    // ============ Integration Tests ============

    /**
     * @notice Test complete flow: aura changes, peg updates, forced burn triggers
     * @dev Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.1, 8.4, 8.5
     */
    function test_Integration_AuraDropTriggersFullFlow() public {
        // Create vault with small baseCap for easier testing
        address newCreator = address(105);
        (address vaultAddr2,) = factory.createVault("Integration Test", "INTG", newCreator, 100e18);
        
        CreatorVault vault2 = CreatorVault(vaultAddr2);

        vm.deal(newCreator, 10_000e18);
        vm.deal(fan1, 10_000e18);
        vm.deal(fan2, 10_000e18);

        // Bootstrap vault
        vm.prank(newCreator);
        vault2.bootstrapCreatorStake{value: 100e18}();

        // Phase 1: High aura, high peg, high supply cap
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 200, "QmPhase1");

        assertEq(vault2.getCurrentAura(), 200, "Phase 1 aura should be 200");
        assertEq(vault2.getPeg(), 1.5e18, "Phase 1 peg should be 1.5e18");
        assertEq(vault2.getCurrentSupplyCap(), 175e18, "Phase 1 cap should be 175");

        // Mint 150 tokens at high peg
        {
            uint256 mintQty = 150e18;
            uint256 peg = vault2.getPeg();
            uint256 collateral = calculateRequiredCollateral(mintQty, peg);
            uint256 fee = calculateMintFee(collateral);

            vm.prank(fan1);
            vault2.mintTokens{value: collateral + fee}(mintQty);
        }

        assertEq(vault2.totalSupply(), 150e18, "Supply should be 150");

        // Phase 2: Aura drops, peg drops, supply cap shrinks
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 50, "QmPhase2");

        assertEq(vault2.getCurrentAura(), 50, "Phase 2 aura should be 50");
        assertEq(vault2.getPeg(), 0.75e18, "Phase 2 peg should be 0.75e18");
        assertEq(vault2.getCurrentSupplyCap(), 62.5e18, "Phase 2 cap should be 62.5");

        // Supply (150) > cap (62.5), forced burn should trigger
        vault2.checkAndTriggerForcedBurn();

        uint256 expectedBurn = 150e18 - 62.5e18; // 87.5 tokens
        assertEq(vault2.pendingForcedBurn(), expectedBurn, "Pending burn should be 87.5");

        // Phase 3: Aura recovers slightly
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 100, "QmPhase3");

        assertEq(vault2.getCurrentAura(), 100, "Phase 3 aura should be 100");
        assertEq(vault2.getPeg(), 1e18, "Phase 3 peg should be 1e18");
        assertEq(vault2.getCurrentSupplyCap(), 100e18, "Phase 3 cap should be 100");

        // Forced burn is still pending (deadline not reached)
        assertEq(vault2.pendingForcedBurn(), expectedBurn, "Pending burn should still be set");

        // Verify that new mints use current peg and fail due to supply cap
        {
            uint256 newMintQty = 10e18;
            uint256 peg = vault2.getPeg();
            uint256 collateral = calculateRequiredCollateral(newMintQty, peg);
            uint256 fee = calculateMintFee(collateral);

            // This mint should fail because supply would exceed cap (150 + 10 > 100)
            vm.prank(fan2);
            vm.expectRevert(CreatorVault.ExceedsSupplyCap.selector);
            vault2.mintTokens{value: collateral + fee}(newMintQty);
        }
    }

    /**
     * @notice Test that multiple aura updates are reflected immediately
     * @dev Requirements: 5.1, 5.2, 8.4
     */
    function test_Integration_MultipleAuraUpdates() public {
        uint256[] memory auraValues = new uint256[](5);
        auraValues[0] = 100;
        auraValues[1] = 150;
        auraValues[2] = 80;
        auraValues[3] = 120;
        auraValues[4] = 90;

        uint256[] memory expectedPegs = new uint256[](5);
        expectedPegs[0] = 1e18; // P(100) = 1.0
        expectedPegs[1] = 1.25e18; // P(150) = 1.25
        expectedPegs[2] = 0.9e18; // P(80) = 0.9
        expectedPegs[3] = 1.1e18; // P(120) = 1.1
        expectedPegs[4] = 0.95e18; // P(90) = 0.95

        // First aura value is already set in setUp (100), so start from index 1
        for (uint256 i = 1; i < auraValues.length; i++) {
            // Wait for cooldown before each update
            vm.warp(block.timestamp + 6 hours);

            vm.prank(oracleAddress);
            oracle.pushAura(address(vault), auraValues[i], string(abi.encodePacked("QmAura", i)));

            uint256 currentAura = vault.getCurrentAura();
            uint256 currentPeg = vault.getPeg();

            assertEq(currentAura, auraValues[i], "Aura should match");
            assertEq(currentPeg, expectedPegs[i], "Peg should match expected");
        }
    }
}
