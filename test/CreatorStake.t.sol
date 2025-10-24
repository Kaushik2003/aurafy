// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {CreatorVault} from "../contracts/CreatorVault.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

/**
 * @title CreatorStakeTest
 * @notice Comprehensive unit tests for creator stake functions
 * @dev Tests bootstrapCreatorStake and unlockStage functions
 *      Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
 */
contract CreatorStakeTest is Test {
    VaultFactory public factory;
    Treasury public treasury;
    AuraOracle public oracle;
    CreatorVault public vault;
    CreatorToken public token;

    address public owner = address(1);
    address public oracleAddress = address(2);
    address public creator = address(3);
    address public nonCreator = address(4);

    // Events (must be declared in test contract for vm.expectEmit)
    event StageUnlocked(address indexed vault, uint8 stage, uint256 stakeAmount);

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

        // Fund creator with CELO for testing
        vm.deal(creator, 10_000e18);

        // Initialize aura in oracle (A_REF = 100 gives BASE_PRICE peg)
        vm.prank(oracleAddress);
        oracle.pushAura(address(vault), 100, "QmInitialAura");
    }

    // ============ bootstrapCreatorStake Tests ============

    /**
     * @notice Test bootstrapCreatorStake with sufficient stake for stage 1
     * @dev Requirements: 2.1, 2.2
     */
    function test_BootstrapCreatorStake_SufficientForStage1() public {
        // Stage 1 requires 100 CELO
        uint256 stakeAmount = 100e18;

        // Get initial state
        assertEq(vault.stage(), 0, "Initial stage should be 0");
        assertEq(vault.creatorCollateral(), 0, "Initial creator collateral should be 0");
        assertEq(vault.totalCollateral(), 0, "Initial total collateral should be 0");

        // Expect StageUnlocked event
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 1, stakeAmount);

        // Bootstrap with sufficient stake
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: stakeAmount}();

        // Verify stage was unlocked
        assertEq(vault.stage(), 1, "Stage should be unlocked to 1");
        assertEq(vault.creatorCollateral(), stakeAmount, "Creator collateral should be updated");
        assertEq(vault.totalCollateral(), stakeAmount, "Total collateral should be updated");
    }

    /**
     * @notice Test bootstrapCreatorStake with more than sufficient stake for stage 1
     * @dev Requirements: 2.1, 2.2
     */
    function test_BootstrapCreatorStake_ExcessStakeForStage1() public {
        // Stage 1 requires 100 CELO, deposit 150 CELO
        uint256 stakeAmount = 150e18;

        // Expect StageUnlocked event with the actual stake amount
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 1, stakeAmount);

        // Bootstrap with excess stake
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: stakeAmount}();

        // Verify stage was unlocked and collateral recorded correctly
        assertEq(vault.stage(), 1, "Stage should be unlocked to 1");
        assertEq(vault.creatorCollateral(), stakeAmount, "Creator collateral should be full amount");
        assertEq(vault.totalCollateral(), stakeAmount, "Total collateral should be full amount");
    }

    /**
     * @notice Test bootstrapCreatorStake with insufficient stake (stage remains 0)
     * @dev Requirements: 2.1, 2.2
     */
    function test_BootstrapCreatorStake_InsufficientStake() public {
        // Stage 1 requires 100 CELO, deposit only 50 CELO
        uint256 stakeAmount = 50e18;

        // Bootstrap with insufficient stake (no event should be emitted)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: stakeAmount}();

        // Verify stage remains 0 but collateral is recorded
        assertEq(vault.stage(), 0, "Stage should remain 0");
        assertEq(vault.creatorCollateral(), stakeAmount, "Creator collateral should be recorded");
        assertEq(vault.totalCollateral(), stakeAmount, "Total collateral should be recorded");
    }

    /**
     * @notice Test bootstrapCreatorStake with exact minimum stake for stage 1
     * @dev Requirements: 2.1, 2.2
     */
    function test_BootstrapCreatorStake_ExactMinimumStake() public {
        // Stage 1 requires exactly 100 CELO
        uint256 stakeAmount = 100e18;

        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 1, stakeAmount);

        vm.prank(creator);
        vault.bootstrapCreatorStake{value: stakeAmount}();

        assertEq(vault.stage(), 1, "Stage should be unlocked to 1");
        assertEq(vault.creatorCollateral(), stakeAmount, "Creator collateral should match");
    }

    /**
     * @notice Test bootstrapCreatorStake can be called multiple times
     * @dev Requirements: 2.1, 2.2
     */
    function test_BootstrapCreatorStake_MultipleCalls() public {
        // First call with insufficient stake
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 30e18}();

        assertEq(vault.stage(), 0, "Stage should remain 0 after first call");
        assertEq(vault.creatorCollateral(), 30e18, "Creator collateral should be 30");

        // Second call with more stake (total now 80, still insufficient)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 50e18}();

        assertEq(vault.stage(), 0, "Stage should remain 0 after second call");
        assertEq(vault.creatorCollateral(), 80e18, "Creator collateral should be 80");

        // Third call to reach threshold (total now 120, sufficient)
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 1, 120e18);

        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 40e18}();

        assertEq(vault.stage(), 1, "Stage should be unlocked to 1");
        assertEq(vault.creatorCollateral(), 120e18, "Creator collateral should be 120");
    }

    /**
     * @notice Test bootstrapCreatorStake reverts when called by non-creator
     * @dev Requirements: 2.1
     */
    function test_RevertWhen_NonCreatorBootstraps() public {
        vm.deal(nonCreator, 1000e18);
        
        vm.expectRevert(CreatorVault.Unauthorized.selector);
        vm.prank(nonCreator);
        vault.bootstrapCreatorStake{value: 100e18}();
    }

    /**
     * @notice Test bootstrapCreatorStake reverts with zero value
     * @dev Requirements: 2.1
     */
    function test_RevertWhen_BootstrapWithZeroValue() public {
        vm.prank(creator);
        vm.expectRevert(CreatorVault.InsufficientPayment.selector);
        vault.bootstrapCreatorStake{value: 0}();
    }

    /**
     * @notice Test collateral accounting is correct after bootstrap
     * @dev Requirements: 2.1
     */
    function test_BootstrapCreatorStake_CollateralAccounting() public {
        uint256 stakeAmount = 200e18;

        vm.prank(creator);
        vault.bootstrapCreatorStake{value: stakeAmount}();

        // Verify all collateral values
        assertEq(vault.creatorCollateral(), stakeAmount, "Creator collateral should match stake");
        assertEq(vault.fanCollateral(), 0, "Fan collateral should remain 0");
        assertEq(vault.totalCollateral(), stakeAmount, "Total collateral should equal creator collateral");
    }

    // ============ unlockStage Tests ============

    /**
     * @notice Test unlockStage progression from stage 1 to 2
     * @dev Requirements: 2.3, 2.4, 2.5
     */
    function test_UnlockStage_Stage1To2() public {
        // Bootstrap to stage 1 (requires 100 CELO)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        assertEq(vault.stage(), 1, "Should be at stage 1");

        // Stage 2 requires 300 CELO cumulative, we have 100, need 200 more
        uint256 additionalStake = 200e18;

        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 2, 300e18);

        vm.prank(creator);
        vault.unlockStage{value: additionalStake}();

        assertEq(vault.stage(), 2, "Should be at stage 2");
        assertEq(vault.creatorCollateral(), 300e18, "Creator collateral should be 300");
        assertEq(vault.totalCollateral(), 300e18, "Total collateral should be 300");
    }

    /**
     * @notice Test unlockStage progression from stage 2 to 3
     * @dev Requirements: 2.3, 2.4, 2.5
     */
    function test_UnlockStage_Stage2To3() public {
        // Bootstrap to stage 1 and then to stage 2
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        assertEq(vault.stage(), 2, "Should be at stage 2");

        // Stage 3 requires 800 CELO cumulative, we have 300, need 500 more
        uint256 additionalStake = 500e18;

        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 3, 800e18);

        vm.prank(creator);
        vault.unlockStage{value: additionalStake}();

        assertEq(vault.stage(), 3, "Should be at stage 3");
        assertEq(vault.creatorCollateral(), 800e18, "Creator collateral should be 800");
    }

    /**
     * @notice Test unlockStage progression from stage 3 to 4
     * @dev Requirements: 2.3, 2.4, 2.5
     */
    function test_UnlockStage_Stage3To4() public {
        // Bootstrap to stage 3
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        vm.prank(creator);
        vault.unlockStage{value: 500e18}();

        assertEq(vault.stage(), 3, "Should be at stage 3");

        // Stage 4 requires 1800 CELO cumulative, we have 800, need 1000 more
        uint256 additionalStake = 1000e18;

        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 4, 1800e18);

        vm.prank(creator);
        vault.unlockStage{value: additionalStake}();

        assertEq(vault.stage(), 4, "Should be at stage 4");
        assertEq(vault.creatorCollateral(), 1800e18, "Creator collateral should be 1800");
    }

    /**
     * @notice Test unlockStage with insufficient additional stake reverts
     * @dev Requirements: 2.4
     */
    function test_RevertWhen_UnlockStageWithInsufficientStake() public {
        // Bootstrap to stage 1
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Try to unlock stage 2 with insufficient additional stake
        // Stage 2 requires 300 CELO cumulative, we have 100, need 200 more, but only send 100
        vm.prank(creator);
        vm.expectRevert(CreatorVault.InsufficientCollateral.selector);
        vault.unlockStage{value: 100e18}();

        // Verify stage remains at 1
        assertEq(vault.stage(), 1, "Stage should remain at 1");
    }

    /**
     * @notice Test unlockStage with exact required additional stake
     * @dev Requirements: 2.3, 2.4
     */
    function test_UnlockStage_ExactRequiredStake() public {
        // Bootstrap to stage 1
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Unlock stage 2 with exact required additional stake (200 CELO)
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 2, 300e18);

        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        assertEq(vault.stage(), 2, "Should be at stage 2");
        assertEq(vault.creatorCollateral(), 300e18, "Creator collateral should be exactly 300");
    }

    /**
     * @notice Test unlockStage with excess stake
     * @dev Requirements: 2.3, 2.4
     */
    function test_UnlockStage_ExcessStake() public {
        // Bootstrap to stage 1
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Unlock stage 2 with excess stake (need 200, send 300)
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 2, 400e18);

        vm.prank(creator);
        vault.unlockStage{value: 300e18}();

        assertEq(vault.stage(), 2, "Should be at stage 2");
        assertEq(vault.creatorCollateral(), 400e18, "Creator collateral should be 400");
    }

    /**
     * @notice Test unlockStage reverts when called from stage 0
     * @dev Requirements: 2.3
     */
    function test_RevertWhen_UnlockStageFromStage0() public {
        // Try to unlock stage without bootstrapping first
        vm.prank(creator);
        vm.expectRevert(CreatorVault.StageNotUnlocked.selector);
        vault.unlockStage{value: 300e18}();

        assertEq(vault.stage(), 0, "Stage should remain at 0");
    }

    /**
     * @notice Test unlockStage reverts when called by non-creator
     * @dev Requirements: 2.3
     */
    function test_RevertWhen_NonCreatorUnlocksStage() public {
        // Bootstrap to stage 1 first
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Try to unlock stage as non-creator
        vm.deal(nonCreator, 1000e18);
        vm.prank(nonCreator);
        vm.expectRevert(CreatorVault.Unauthorized.selector);
        vault.unlockStage{value: 200e18}();
    }

    /**
     * @notice Test unlockStage reverts with zero value
     * @dev Requirements: 2.3
     */
    function test_RevertWhen_UnlockStageWithZeroValue() public {
        // Bootstrap to stage 1 first
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Try to unlock stage with zero value
        vm.prank(creator);
        vm.expectRevert(CreatorVault.InsufficientPayment.selector);
        vault.unlockStage{value: 0}();
    }

    /**
     * @notice Test StageUnlocked event emissions
     * @dev Requirements: 2.2, 2.5
     */
    function test_StageUnlocked_EventEmissions() public {
        // Test event for stage 1 unlock via bootstrap
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 1, 100e18);

        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        // Test event for stage 2 unlock
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 2, 300e18);

        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        // Test event for stage 3 unlock
        vm.expectEmit(true, false, false, true);
        emit StageUnlocked(address(vault), 3, 800e18);

        vm.prank(creator);
        vault.unlockStage{value: 500e18}();
    }

    /**
     * @notice Test collateral accounting through multiple stage unlocks
     * @dev Requirements: 2.1, 2.3
     */
    function test_CollateralAccounting_ThroughStageProgression() public {
        // Bootstrap to stage 1
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();

        assertEq(vault.creatorCollateral(), 100e18, "Creator collateral should be 100");
        assertEq(vault.fanCollateral(), 0, "Fan collateral should be 0");
        assertEq(vault.totalCollateral(), 100e18, "Total collateral should be 100");

        // Unlock stage 2
        vm.prank(creator);
        vault.unlockStage{value: 200e18}();

        assertEq(vault.creatorCollateral(), 300e18, "Creator collateral should be 300");
        assertEq(vault.fanCollateral(), 0, "Fan collateral should be 0");
        assertEq(vault.totalCollateral(), 300e18, "Total collateral should be 300");

        // Unlock stage 3
        vm.prank(creator);
        vault.unlockStage{value: 500e18}();

        assertEq(vault.creatorCollateral(), 800e18, "Creator collateral should be 800");
        assertEq(vault.fanCollateral(), 0, "Fan collateral should be 0");
        assertEq(vault.totalCollateral(), 800e18, "Total collateral should be 800");

        // Unlock stage 4
        vm.prank(creator);
        vault.unlockStage{value: 1000e18}();

        assertEq(vault.creatorCollateral(), 1800e18, "Creator collateral should be 1800");
        assertEq(vault.fanCollateral(), 0, "Fan collateral should be 0");
        assertEq(vault.totalCollateral(), 1800e18, "Total collateral should be 1800");
    }

    /**
     * @notice Test full stage progression from 0 to 4
     * @dev Requirements: 2.1, 2.2, 2.3, 2.4, 2.5
     */
    function test_FullStageProgression_0To4() public {
        // Start at stage 0
        assertEq(vault.stage(), 0, "Should start at stage 0");

        // Bootstrap to stage 1 (100 CELO)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();
        assertEq(vault.stage(), 1, "Should be at stage 1");

        // Unlock stage 2 (300 CELO cumulative, need 200 more)
        vm.prank(creator);
        vault.unlockStage{value: 200e18}();
        assertEq(vault.stage(), 2, "Should be at stage 2");

        // Unlock stage 3 (800 CELO cumulative, need 500 more)
        vm.prank(creator);
        vault.unlockStage{value: 500e18}();
        assertEq(vault.stage(), 3, "Should be at stage 3");

        // Unlock stage 4 (1800 CELO cumulative, need 1000 more)
        vm.prank(creator);
        vault.unlockStage{value: 1000e18}();
        assertEq(vault.stage(), 4, "Should be at stage 4");

        // Verify final collateral
        assertEq(vault.creatorCollateral(), 1800e18, "Final creator collateral should be 1800");
        assertEq(vault.totalCollateral(), 1800e18, "Final total collateral should be 1800");
    }

    /**
     * @notice Test that stages can only increment by 1
     * @dev Requirements: 2.5
     */
    function test_StageIncrementsOnlyByOne() public {
        // Bootstrap to stage 1
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 100e18}();
        assertEq(vault.stage(), 1, "Should be at stage 1");

        // Even with enough collateral for stage 3, should only unlock stage 2
        vm.prank(creator);
        vault.unlockStage{value: 200e18}();
        assertEq(vault.stage(), 2, "Should be at stage 2, not higher");

        // Need another call to reach stage 3
        vm.prank(creator);
        vault.unlockStage{value: 500e18}();
        assertEq(vault.stage(), 3, "Should be at stage 3");
    }

    /**
     * @notice Test bootstrap with enough for multiple stages only unlocks stage 1
     * @dev Requirements: 2.2
     */
    function test_BootstrapWithExcessOnlyUnlocksStage1() public {
        // Bootstrap with 1000 CELO (enough for stage 4)
        vm.prank(creator);
        vault.bootstrapCreatorStake{value: 1000e18}();

        // Should only unlock stage 1, not jump to higher stages
        assertEq(vault.stage(), 1, "Should only unlock stage 1");
        assertEq(vault.creatorCollateral(), 1000e18, "Collateral should be recorded");
    }
}
