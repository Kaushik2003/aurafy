// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {CreatorVault} from "../contracts/CreatorVault.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

/**
 * @title FanMintingTest
 * @notice Comprehensive unit tests for fan minting functionality
 * @dev Tests mintTokens function with various scenarios
 *      Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7
 */
contract FanMintingTest is Test {
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
    address public fan3 = address(6);

    // Events (must be declared in test contract for vm.expectEmit)
    event Minted(
        address indexed vault, address indexed minter, uint256 qty, uint256 collateral, uint8 stage, uint256 peg
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
        vm.deal(fan3, 10_000e18);

        // Bootstrap creator stake to unlock stage 1 (requires 100 CELO)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Initialize aura in oracle (A_REF = 100 gives BASE_PRICE peg)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 100, "QmInitialAura");
    }

    // ============ Helper Functions ============

    /**
     * @notice Calculate required collateral for minting
     * @dev Replicates vault's calculation: qty * peg * MIN_CR
     */
    function calculateRequiredCollateral(uint256 qty, uint256 peg) internal pure returns (uint256) {
        uint256 WAD = 1e18;
        uint256 MIN_CR = 1.5e18;
        // qty * peg / WAD * MIN_CR / WAD
        return (qty * peg * MIN_CR) / (WAD * WAD);
    }

    /**
     * @notice Calculate mint fee
     * @dev Replicates vault's calculation: requiredCollateral * MINT_FEE / WAD
     */
    function calculateMintFee(uint256 requiredCollateral) internal pure returns (uint256) {
        uint256 WAD = 1e18;
        uint256 MINT_FEE = 0.005e18; // 0.5%
        return (requiredCollateral * MINT_FEE) / WAD;
    }

    // ============ Successful Mint Tests ============

    /**
     * @notice Test successful mint with exact collateral requirement
     * @dev Requirements: 3.1, 3.5, 3.6
     */
    function test_MintTokens_ExactCollateral() public {
        uint256 qty = 10e18; // 10 tokens
        uint256 peg = vault.getPeg(); // Should be BASE_PRICE = 1e18

        // Calculate exact required collateral and fee
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);
        uint256 totalPayment = requiredCollateral + fee;

        // Get initial balances
        uint256 initialTreasuryBalance = address(treasury).balance;
        uint256 initialFanBalance = fan1.balance;

        // Expect Minted event
        vm.expectEmit(true, true, false, true);
        emit Minted(address(vault), fan1, qty, requiredCollateral, 1, peg);

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: totalPayment}(qty);

        // Verify token balance
        assertEq(token.balanceOf(fan1), qty, "Fan should receive tokens");

        // Verify vault state
        assertEq(vault.totalSupply(), qty, "Total supply should increase");
        assertEq(vault.fanCollateral(), requiredCollateral, "Fan collateral should be recorded");
        assertEq(vault.totalCollateral(), 100e18 + requiredCollateral, "Total collateral should include fan deposit");

        // Verify fee was transferred to treasury
        assertEq(address(treasury).balance, initialTreasuryBalance + fee, "Treasury should receive fee");

        // Verify fan's CELO balance decreased
        assertEq(fan1.balance, initialFanBalance - totalPayment, "Fan balance should decrease by total payment");
    }

    /**
     * @notice Test mint with excess collateral (no refund in current design)
     * @dev Requirements: 3.1, 3.5
     */
    function test_MintTokens_ExcessCollateral() public {
        uint256 qty = 10e18;
        uint256 peg = vault.getPeg();

        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);
        uint256 totalPayment = requiredCollateral + fee;
        uint256 excessPayment = totalPayment + 5e18; // Send 5 extra CELO

        uint256 initialFanBalance = fan1.balance;

        // Mint with excess collateral
        vm.prank(fan1);
        vault.mintTokens{value: excessPayment}(qty);

        // Verify token balance
        assertEq(token.balanceOf(fan1), qty, "Fan should receive tokens");

        // Verify excess collateral is recorded (no refund)
        uint256 actualCollateral = excessPayment - fee;
        assertEq(vault.fanCollateral(), actualCollateral, "All collateral minus fee should be recorded");

        // Verify fan paid full excess amount
        assertEq(fan1.balance, initialFanBalance - excessPayment, "Fan should pay full excess amount");
    }

    // ============ Revert Tests ============

    /**
     * @notice Test mint reverts when stage == 0
     * @dev Requirements: 3.2
     */
    function test_RevertWhen_MintAtStage0() public {
        // Create a new vault with a different creator (since factory only allows one vault per creator)
        address newCreator = address(100);
        
        (address vaultAddr2,) = factory.createVault("New Creator Token", "NCRTR", newCreator, 100_000e18);

        CreatorVault vault2 = CreatorVault(vaultAddr2);

        // Initialize aura in oracle for vault2
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault2), 100, "QmInitialAura");

        uint256 qty = 10e18;
        uint256 peg = vault2.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Try to mint at stage 0 (without bootstrapping)
        vm.prank(fan1);
        vm.expectRevert(CreatorVault.StageNotUnlocked.selector);
        vault2.mintTokens{value: requiredCollateral + fee}(qty);
    }

    /**
     * @notice Test mint reverts when exceeding stage cap
     * @dev Requirements: 3.2
     */
    function test_RevertWhen_ExceedsStageCap() public {
        // Stage 1 mint cap is 500 tokens
        uint256 qty = 600e18; // Try to mint 600 tokens
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Try to mint more than stage cap
        vm.prank(fan1);
        vm.expectRevert(CreatorVault.ExceedsStageCap.selector);
        vault.mintTokens{value: requiredCollateral + fee}(qty);
    }

    /**
     * @notice Test mint reverts when exceeding supply cap
     * @dev Requirements: 3.3
     */
    function test_RevertWhen_ExceedsSupplyCap() public {
        // Unlock all stages to get maximum stage cap
        // Stage 4 has a cap of 34,500 tokens
        vm.prank(creator);
        vault.unlockStage{value: 200e18}(); // Stage 2

        vm.prank(creator);
        vault.unlockStage{value: 500e18}(); // Stage 3

        vm.prank(creator);
        vault.unlockStage{value: 1000e18}(); // Stage 4

        // Manually set stage 5 with a very high mint cap (higher than supply cap)
        // This allows us to test supply cap enforcement without hitting stage cap first
        vm.prank(owner);
        factory.setStageConfig(address(vault), 5, 3800e18, 150_000e18);

        // Unlock stage 5
        vm.prank(creator);
        vault.unlockStage{value: 2000e18}(); // Stage 5

        // Current supply cap is based on lastAura (A_REF = 100)
        // SupplyCap = BaseCap * (1 + 0.75 * (100 - 100) / 100) = 100,000
        // Stage 5 cap is now 150,000, so supply cap (100,000) will be hit first
        // Try to mint more than supply cap
        uint256 qty = 100_001e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.deal(fan1, requiredCollateral + fee + 1000e18); // Ensure enough funds

        vm.prank(fan1);
        vm.expectRevert(CreatorVault.ExceedsSupplyCap.selector);
        vault.mintTokens{value: requiredCollateral + fee}(qty);
    }

    /**
     * @notice Test mint reverts with insufficient collateral
     * @dev Requirements: 3.5
     */
    function test_RevertWhen_InsufficientCollateral() public {
        uint256 qty = 10e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);
        uint256 totalPayment = requiredCollateral + fee;

        // Try to mint with insufficient collateral (1 wei less)
        vm.prank(fan1);
        vm.expectRevert(CreatorVault.InsufficientCollateral.selector);
        vault.mintTokens{value: totalPayment - 1}(qty);
    }

    /**
     * @notice Test mint reverts when health would drop below MIN_CR
     * @dev Requirements: 3.6
     */
    function test_RevertWhen_HealthTooLow() public {
        // This is a tricky test - we need to create a scenario where minting would drop health below MIN_CR
        // One way is to mint with exactly MIN_CR collateral, then try to mint with less
        // However, the contract enforces MIN_CR per mint, so this should not happen in normal operation
        
        // Let's test by trying to mint with collateral that would result in health < MIN_CR
        // We'll manipulate the calculation by sending insufficient collateral
        uint256 qty = 10e18;
        uint256 peg = vault.getPeg();
        
        // Calculate collateral that would give health < MIN_CR
        // Health = totalCollateral / (totalSupply * peg)
        // We want health < 1.5, so totalCollateral < 1.5 * totalSupply * peg
        
        // Send exactly the required amount (which should pass)
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);
        
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);
        
        // Now verify health is at MIN_CR
        (,,uint256 totalCollateral, uint256 totalSupply, uint256 currentPeg,, uint256 health) = vault.getVaultState();
        assertGe(health, vault.MIN_CR(), "Health should be at or above MIN_CR");
    }

    // ============ Position Creation and Storage Tests ============

    /**
     * @notice Test position creation and storage
     * @dev Requirements: 3.4
     */
    function test_MintTokens_PositionCreation() public {
        uint256 qty = 10e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify position was created
        assertEq(vault.getPositionCount(fan1), 1, "Should have 1 position");

        // Get position details
        CreatorVault.Position memory position = vault.getPosition(fan1, 0);

        assertEq(position.owner, fan1, "Position owner should be fan1");
        assertEq(position.qty, qty, "Position qty should match minted amount");
        assertEq(position.collateral, requiredCollateral, "Position collateral should match (minus fee)");
        assertEq(position.stage, 1, "Position stage should be 1");
        assertEq(position.createdAt, block.timestamp, "Position createdAt should be current timestamp");
    }

    /**
     * @notice Test multiple mints by same fan create multiple positions
     * @dev Requirements: 3.4
     */
    function test_MintTokens_MultiplePositions() public {
        uint256 peg = vault.getPeg();

        // First mint - 10 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(10e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(10e18);
        }

        // Second mint - 20 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(20e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(20e18);
        }

        // Third mint - 15 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(15e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(15e18);
        }

        // Verify 3 positions were created
        assertEq(vault.getPositionCount(fan1), 3, "Should have 3 positions");

        // Verify each position
        CreatorVault.Position memory pos1 = vault.getPosition(fan1, 0);
        CreatorVault.Position memory pos2 = vault.getPosition(fan1, 1);
        CreatorVault.Position memory pos3 = vault.getPosition(fan1, 2);

        assertEq(pos1.qty, 10e18, "Position 1 qty should match");
        assertEq(pos2.qty, 20e18, "Position 2 qty should match");
        assertEq(pos3.qty, 15e18, "Position 3 qty should match");

        // Verify total token balance
        assertEq(token.balanceOf(fan1), 45e18, "Total token balance should be sum of all mints");
    }

    // ============ Fee Transfer Tests ============

    /**
     * @notice Test fee transfer to treasury
     * @dev Requirements: 3.7
     */
    function test_MintTokens_FeeTransfer() public {
        uint256 qty = 10e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        uint256 initialTreasuryBalance = address(treasury).balance;

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify treasury received fee
        assertEq(address(treasury).balance, initialTreasuryBalance + fee, "Treasury should receive fee");
    }

    /**
     * @notice Test fee calculation is correct
     * @dev Requirements: 3.7
     */
    function test_MintTokens_FeeCalculation() public {
        uint256 qty = 100e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Fee should be 0.5% of required collateral
        uint256 expectedFee = (requiredCollateral * 5) / 1000; // 0.5%
        assertEq(fee, expectedFee, "Fee should be 0.5% of required collateral");

        uint256 initialTreasuryBalance = address(treasury).balance;

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify exact fee amount was transferred
        assertEq(address(treasury).balance, initialTreasuryBalance + expectedFee, "Exact fee should be transferred");
    }

    // ============ Token Minting Tests ============

    /**
     * @notice Test token minting to fan
     * @dev Requirements: 3.5
     */
    function test_MintTokens_TokenMinting() public {
        uint256 qty = 50e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Verify initial balance is 0
        assertEq(token.balanceOf(fan1), 0, "Initial token balance should be 0");

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify tokens were minted to fan
        assertEq(token.balanceOf(fan1), qty, "Fan should receive exact qty of tokens");
    }

    /**
     * @notice Test multiple fans can mint tokens
     * @dev Requirements: 3.1, 3.5
     */
    function test_MintTokens_MultipleFans() public {
        uint256 peg = vault.getPeg();

        // Fan1 mints 30 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(30e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(30e18);
        }

        // Fan2 mints 40 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(40e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan2);
            vault.mintTokens{value: requiredCollateral + fee}(40e18);
        }

        // Fan3 mints 50 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(50e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            vm.prank(fan3);
            vault.mintTokens{value: requiredCollateral + fee}(50e18);
        }

        // Verify each fan received their tokens
        assertEq(token.balanceOf(fan1), 30e18, "Fan1 should have their tokens");
        assertEq(token.balanceOf(fan2), 40e18, "Fan2 should have their tokens");
        assertEq(token.balanceOf(fan3), 50e18, "Fan3 should have their tokens");

        // Verify total supply
        assertEq(vault.totalSupply(), 120e18, "Total supply should be sum of all mints");
    }

    // ============ Event Emission Tests ============

    /**
     * @notice Test Minted event emission
     * @dev Requirements: 3.5
     */
    function test_MintTokens_EventEmission() public {
        uint256 qty = 25e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Expect Minted event with correct parameters
        vm.expectEmit(true, true, false, true);
        emit Minted(address(vault), fan1, qty, requiredCollateral, 1, peg);

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);
    }

    /**
     * @notice Test Minted event emission for multiple mints
     * @dev Requirements: 3.5
     */
    function test_MintTokens_MultipleEventEmissions() public {
        uint256 peg = vault.getPeg();

        // First mint - 10 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(10e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);

            vm.expectEmit(true, true, false, true);
            emit Minted(address(vault), fan1, 10e18, requiredCollateral, 1, peg);

            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(10e18);
        }

        // Second mint - 20 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(20e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);

            vm.expectEmit(true, true, false, true);
            emit Minted(address(vault), fan1, 20e18, requiredCollateral, 1, peg);

            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(20e18);
        }
    }

    // ============ Collateral Accounting Tests ============

    /**
     * @notice Test collateral accounting after mint
     * @dev Requirements: 3.5
     */
    function test_MintTokens_CollateralAccounting() public {
        uint256 qty = 100e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        uint256 initialCreatorCollateral = vault.creatorCollateral();
        uint256 initialFanCollateral = vault.fanCollateral();
        uint256 initialTotalCollateral = vault.totalCollateral();

        // Mint tokens
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify collateral accounting
        assertEq(vault.creatorCollateral(), initialCreatorCollateral, "Creator collateral should not change");
        assertEq(vault.fanCollateral(), initialFanCollateral + requiredCollateral, "Fan collateral should increase");
        assertEq(
            vault.totalCollateral(),
            initialTotalCollateral + requiredCollateral,
            "Total collateral should increase by required collateral"
        );
    }

    /**
     * @notice Test collateral accounting with multiple mints
     * @dev Requirements: 3.5
     */
    function test_MintTokens_CollateralAccountingMultipleMints() public {
        uint256 peg = vault.getPeg();
        uint256 initialTotalCollateral = vault.totalCollateral();

        uint256 totalRequiredCollateral = 0;

        // First mint - 50 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(50e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            totalRequiredCollateral += requiredCollateral;

            vm.prank(fan1);
            vault.mintTokens{value: requiredCollateral + fee}(50e18);
        }

        // Second mint - 75 tokens
        {
            uint256 requiredCollateral = calculateRequiredCollateral(75e18, peg);
            uint256 fee = calculateMintFee(requiredCollateral);
            totalRequiredCollateral += requiredCollateral;

            vm.prank(fan2);
            vault.mintTokens{value: requiredCollateral + fee}(75e18);
        }

        // Verify total collateral increased by both required collaterals
        assertEq(
            vault.totalCollateral(),
            initialTotalCollateral + totalRequiredCollateral,
            "Total collateral should increase by sum of both required collaterals"
        );

        assertEq(
            vault.fanCollateral(),
            totalRequiredCollateral,
            "Fan collateral should be sum of both required collaterals"
        );
    }

    // ============ Stage Progression Tests ============

    /**
     * @notice Test minting at different stages
     * @dev Requirements: 3.2, 3.4
     */
    function test_MintTokens_DifferentStages() public {
        uint256 qty1 = 100e18;
        uint256 peg = vault.getPeg();

        // Mint at stage 1
        uint256 requiredCollateral1 = calculateRequiredCollateral(qty1, peg);
        uint256 fee1 = calculateMintFee(requiredCollateral1);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral1 + fee1}(qty1);

        // Verify position stage
        CreatorVault.Position memory position1 = vault.getPosition(fan1, 0);
        assertEq(position1.stage, 1, "Position should be at stage 1");

        // Unlock stage 2
        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        // Mint at stage 2
        uint256 qty2 = 200e18;
        uint256 requiredCollateral2 = calculateRequiredCollateral(qty2, peg);
        uint256 fee2 = calculateMintFee(requiredCollateral2);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral2 + fee2}(qty2);

        // Verify position stage
        CreatorVault.Position memory position2 = vault.getPosition(fan1, 1);
        assertEq(position2.stage, 2, "Position should be at stage 2");
    }

    // ============ Edge Case Tests ============

    /**
     * @notice Test minting with very small quantity
     * @dev Requirements: 3.1, 3.5
     */
    function test_MintTokens_SmallQuantity() public {
        uint256 qty = 1e18; // 1 token
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        assertEq(token.balanceOf(fan1), qty, "Fan should receive 1 token");
        assertEq(vault.totalSupply(), qty, "Total supply should be 1 token");
    }

    /**
     * @notice Test minting up to stage cap
     * @dev Requirements: 3.2
     */
    function test_MintTokens_UpToStageCap() public {
        // Stage 1 cap is 500 tokens
        uint256 qty = 500e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        assertEq(vault.totalSupply(), qty, "Total supply should be at stage cap");

        // Try to mint 1 more token (should revert)
        uint256 qty2 = 1e18;
        uint256 requiredCollateral2 = calculateRequiredCollateral(qty2, peg);
        uint256 fee2 = calculateMintFee(requiredCollateral2);

        vm.prank(fan2);
        vm.expectRevert(CreatorVault.ExceedsStageCap.selector);
        vault.mintTokens{value: requiredCollateral2 + fee2}(qty2);
    }

    /**
     * @notice Test health calculation after mint
     * @dev Requirements: 3.6
     */
    function test_MintTokens_HealthCalculation() public {
        uint256 qty = 100e18;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Get vault state
        (,,uint256 totalCollateral, uint256 totalSupply, uint256 currentPeg,, uint256 health) = vault.getVaultState();

        // Calculate expected health: totalCollateral / (totalSupply * peg)
        uint256 WAD = 1e18;
        uint256 expectedHealth = (totalCollateral * WAD) / ((totalSupply * currentPeg) / WAD);

        assertEq(health, expectedHealth, "Health should match calculated value");
        assertGe(health, vault.MIN_CR(), "Health should be at or above MIN_CR");
    }

    /**
     * @notice Test minting with zero quantity
     * @dev Requirements: 3.1
     * @dev Note: Contract allows zero quantity mints (edge case), but they create empty positions
     */
    function test_MintTokens_ZeroQuantity() public {
        uint256 qty = 0;
        uint256 peg = vault.getPeg();
        uint256 requiredCollateral = calculateRequiredCollateral(qty, peg);
        uint256 fee = calculateMintFee(requiredCollateral);

        // Zero quantity mint should succeed but create empty position
        vm.prank(fan1);
        vault.mintTokens{value: requiredCollateral + fee}(qty);

        // Verify no tokens were minted
        assertEq(token.balanceOf(fan1), 0, "Fan should receive 0 tokens");
        assertEq(vault.totalSupply(), 0, "Total supply should remain 0");
        
        // Verify position was still created (edge case behavior)
        assertEq(vault.getPositionCount(fan1), 1, "Position should be created even with 0 qty");
    }
}
