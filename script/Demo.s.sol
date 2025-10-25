// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../contracts/Treasury.sol";
import "../contracts/AuraOracle.sol";
import "../contracts/VaultFactory.sol";
import "../contracts/CreatorVault.sol";
import "../contracts/CreatorToken.sol";

/**
 * @title Demo
 * @notice Comprehensive end-to-end demonstration script for AuraFi protocol
 * @dev Demonstrates full workflow with mock oracle data for automated testing
 *      For real testnet testing, see DEMO.md for oracle.js integration
 */
contract Demo is Script {
    // Deployed contracts
    Treasury public treasury;
    AuraOracle public oracle;
    VaultFactory public factory;
    CreatorVault public vault;
    CreatorToken public token;

    // Demo actors
    address public deployer;
    address public creator;
    address public fan1;
    address public fan2;
    address public liquidator;

    // Demo parameters
    uint256 public constant DEMO_FID = 1398844;
    uint256 public constant CREATOR_BOOTSTRAP = 100 ether; // 100 CELO for stage 1
    uint256 public constant FAN1_MINT_AMOUNT = 200 ether; // 200 tokens
    uint256 public constant FAN2_MINT_AMOUNT = 150 ether; // 150 tokens

    // Mock aura values for different scenarios
    uint256 public constant INITIAL_AURA = 136; // Healthy state (cap ~1270 tokens)
    uint256 public constant INCREASED_AURA = 175; // Growth scenario (cap ~1562 tokens)
    uint256 public constant DECREASED_AURA = 20; // Forced burn scenario (cap = 250 tokens min, triggers burn with 350 supply)
    uint256 public constant CRITICAL_AURA = 10; // Liquidation scenario (very low peg, cap = 250 tokens min)

    function run() public {
        // Setup demo accounts using Anvil's default accounts
        // These accounts are pre-funded when using Anvil
        deployer = msg.sender; // Account 0: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        creator = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Account 1
        fan1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Account 2
        fan2 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Account 3
        liquidator = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // Account 4

        // Note: When broadcasting, these accounts are already funded by Anvil
        // When simulating locally, we need to fund them
        if (block.chainid == 31337 || tx.origin == address(0)) {
            // Local simulation mode
            vm.deal(creator, 200 ether);
            vm.deal(fan1, 500 ether);
            vm.deal(fan2, 500 ether);
            vm.deal(liquidator, 50 ether);
        }

        console.log("\n");
        console.log("========================================");
        console.log("   AuraFi Protocol - Demo Script");
        console.log("========================================");
        console.log("");

        // Phase 1: Deploy contracts
        _phase1_DeployContracts();

        // Phase 2: Bootstrap creator stake
        _phase2_BootstrapCreator();

        // Phase 3: Initial oracle update (mock)
        _phase3_InitialOracleUpdate();

        // Phase 4: Fan minting at stage 1
        _phase4_FanMinting();

        // Phase 5: Oracle update - increased aura
        _phase5_IncreasedAura();

        // Phase 6: More fan minting at higher peg
        _phase6_MoreMinting();

        // Phase 7: Oracle update - decreased aura (forced burn trigger)
        _phase7_DecreasedAura();

        // Phase 8: Execute forced burn
        _phase8_ForcedBurn();

        // Phase 9: Degrade health and liquidation
        _phase9_Liquidation();

        // Final summary
        _printFinalSummary();
    }

    function _phase1_DeployContracts() internal {
        console.log("=== PHASE 1: Deploy Contracts ===");
        console.log("");

        vm.startBroadcast(deployer);

        // Deploy Treasury
        treasury = new Treasury(deployer);
        console.log("Treasury deployed:", address(treasury));

        // Deploy AuraOracle (deployer is oracle address for demo)
        oracle = new AuraOracle(deployer, deployer);
        console.log("AuraOracle deployed:", address(oracle));

        // Deploy VaultFactory
        factory = new VaultFactory(
            deployer,
            address(treasury),
            address(oracle)
        );
        console.log("VaultFactory deployed:", address(factory));

        vm.stopBroadcast();

        console.log("");
        console.log("Deployment complete!");
        console.log("");
    }

    function _phase2_BootstrapCreator() internal {
        console.log("=== PHASE 2: Bootstrap Creator Stake ===");
        console.log("");

        vm.startBroadcast(deployer);

        // Create vault for demo creator
        (address vaultAddress, address tokenAddress) = factory.createVault(
            "Demo Creator Token",
            "DEMO",
            creator,
            1000 ether
        );
        vault = CreatorVault(payable(vaultAddress));
        token = CreatorToken(tokenAddress);

        console.log("Vault created for creator:", creator);
        console.log("Vault address:", address(vault));
        console.log("Token address:", address(token));
        console.log("Creator FID (off-chain):", DEMO_FID);
        console.log("Base capacity: 1000 tokens");

        vm.stopBroadcast();

        // Creator bootstraps stake
        // Use private key for Anvil account 1
        vm.startBroadcast(
            0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
        );

        vault.bootstrapCreatorStake{value: CREATOR_BOOTSTRAP}();

        vm.stopBroadcast();

        // Log state
        (uint256 creatorColl, , uint256 totalColl, , , uint8 stage, ) = vault
            .getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("");
        console.log(
            "Creator bootstrapped with:",
            CREATOR_BOOTSTRAP / 1 ether,
            "CELO"
        );
        console.log("Stage unlocked:", stage);
        console.log("Creator collateral:", creatorColl / 1 ether, "CELO");
        console.log("Total collateral:", totalColl / 1 ether, "CELO");
        console.log("Current aura:", aura, "(not yet set by oracle)");
        console.log("");
        console.log("NOTE: Aura is 0 until oracle pushes first update");
        console.log("");
    }

    function _phase3_InitialOracleUpdate() internal {
        console.log("=== PHASE 3: Initial Oracle Update (Mock) ===");
        console.log("");
        console.log("In production, run:");
        console.log(
            "  node oracle/oracle.js --vault",
            address(vault),
            "--fid",
            DEMO_FID
        );
        console.log("");
        console.log("For demo, pushing mock aura:", INITIAL_AURA);
        console.log("");

        vm.startBroadcast(deployer);

        // Push initial aura (deployer is oracle address)
        string memory mockIpfsHash = "QmMockInitialMetrics123";
        oracle.pushAura(address(vault), INITIAL_AURA, mockIpfsHash);

        vm.stopBroadcast();

        // Log updated state
        (, , , uint256 supply, uint256 peg, , ) = vault.getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("Oracle update complete!");
        console.log("Aura:", aura);
        console.log("Peg:", peg / 1 ether, "CELO");
        console.log(
            "Supply cap:",
            vault.getCurrentSupplyCap() / 1 ether,
            "tokens"
        );
        console.log("");
    }

    function _phase4_FanMinting() internal {
        console.log("=== PHASE 4: Fan Minting at Stage 1 ===");
        console.log("");

        // Calculate required collateral for fan1
        uint256 peg = vault.getPeg();
        uint256 minCR = vault.MIN_CR();
        uint256 mintFee = vault.MINT_FEE();

        // Required collateral = qty * peg * MIN_CR
        uint256 requiredColl = (FAN1_MINT_AMOUNT * peg * minCR) /
            (1 ether * 1 ether);
        uint256 fee = (requiredColl * mintFee) / 1 ether;
        uint256 totalPayment = requiredColl + fee;

        console.log("Fan1 minting:", FAN1_MINT_AMOUNT / 1 ether, "tokens");
        console.log("Current peg:", peg / 1 ether, "CELO");
        console.log("Required collateral:", requiredColl / 1 ether, "CELO");
        console.log("Mint fee:", fee / 1 ether, "CELO");
        console.log("Total payment:", totalPayment / 1 ether, "CELO");
        console.log("");

        // Use private key for Anvil account 2
        vm.startBroadcast(
            0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
        );
        vault.mintTokens{value: totalPayment}(FAN1_MINT_AMOUNT);
        vm.stopBroadcast();

        // Log state after mint
        (
            uint256 creatorColl,
            uint256 fanColl,
            uint256 totalColl,
            uint256 supply,
            uint256 newPeg,
            uint8 stage,
            uint256 health
        ) = vault.getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("Mint successful!");
        console.log("Fan1 token balance:", token.balanceOf(fan1) / 1 ether);
        console.log("Total supply:", supply / 1 ether, "tokens");
        console.log("Fan collateral:", fanColl / 1 ether, "CELO");
        console.log("Total collateral:", totalColl / 1 ether, "CELO");
        console.log("Health:", health / 1e16, "%");
        console.log("");
    }

    function _phase5_IncreasedAura() internal {
        console.log("=== PHASE 5: Oracle Update - Increased Aura ===");
        console.log("");
        console.log("Simulating creator growth scenario");
        console.log("In production, oracle.js would detect increased metrics");
        console.log("");

        // Wait for cooldown (6 hours)
        console.log("Fast-forwarding time by 6 hours...");
        console.log(
            "Note: When broadcasting to Anvil, use: cast rpc evm_increaseTime 21601"
        );
        vm.warp(block.timestamp + 6 hours + 1);

        vm.startBroadcast(deployer);

        string memory mockIpfsHash = "QmMockIncreasedMetrics456";
        oracle.pushAura(address(vault), INCREASED_AURA, mockIpfsHash);

        vm.stopBroadcast();

        // Log updated state
        (, , , uint256 supply, uint256 peg, , ) = vault.getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("Oracle update complete!");
        console.log("Previous aura:", INITIAL_AURA);
        console.log("New aura:", aura);
        console.log("New peg:", peg / 1 ether, "CELO");
        console.log("Peg increased due to higher aura");
        console.log(
            "New supply cap:",
            vault.getCurrentSupplyCap() / 1 ether,
            "tokens"
        );
        console.log("");
    }

    function _phase6_MoreMinting() internal {
        console.log("=== PHASE 6: More Fan Minting at Higher Peg ===");
        console.log("");

        // Calculate required collateral for fan2 at new higher peg
        uint256 peg = vault.getPeg();
        uint256 minCR = vault.MIN_CR();
        uint256 mintFee = vault.MINT_FEE();

        uint256 requiredColl = (FAN2_MINT_AMOUNT * peg * minCR) /
            (1 ether * 1 ether);
        uint256 fee = (requiredColl * mintFee) / 1 ether;
        uint256 totalPayment = requiredColl + fee;

        console.log("Fan2 minting:", FAN2_MINT_AMOUNT / 1 ether, "tokens");
        console.log("Current peg:", peg / 1 ether, "CELO (higher than before)");
        console.log("Required collateral:", requiredColl / 1 ether, "CELO");
        console.log("Total payment:", totalPayment / 1 ether, "CELO");
        console.log("");

        // Use private key for Anvil account 3
        vm.startBroadcast(
            0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6
        );
        vault.mintTokens{value: totalPayment}(FAN2_MINT_AMOUNT);
        vm.stopBroadcast();

        // Log state
        (, , uint256 totalColl, uint256 supply, , , uint256 health) = vault
            .getVaultState();

        console.log("Mint successful!");
        console.log("Fan2 token balance:", token.balanceOf(fan2) / 1 ether);
        console.log("Total supply:", supply / 1 ether, "tokens");
        console.log("Total collateral:", totalColl / 1 ether, "CELO");
        console.log("Health:", health / 1e16, "%");
        console.log("");
    }

    function _phase7_DecreasedAura() internal {
        console.log(
            "=== PHASE 7: Oracle Update - Decreased Aura (Forced Burn) ==="
        );
        console.log("");
        console.log("Simulating creator decline scenario");
        console.log("Aura drops significantly, triggering supply cap shrink");
        console.log("");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours + 1);

        uint256 supplyBefore = vault.totalSupply();
        uint256 capBefore = vault.getCurrentSupplyCap();

        vm.startBroadcast(deployer);

        string memory mockIpfsHash = "QmMockDecreasedMetrics789";
        oracle.pushAura(address(vault), DECREASED_AURA, mockIpfsHash);

        vm.stopBroadcast();

        // Check and trigger forced burn
        uint256 capAfter = vault.getCurrentSupplyCap();

        console.log("Oracle update complete!");
        console.log("Previous aura:", INCREASED_AURA);
        console.log("New aura:", DECREASED_AURA);
        console.log("Supply:", supplyBefore / 1 ether, "tokens");
        console.log("Previous cap:", capBefore / 1 ether, "tokens");
        console.log("New cap:", capAfter / 1 ether, "tokens");
        console.log("");

        if (supplyBefore > capAfter) {
            console.log("Supply exceeds cap! Triggering forced burn...");
            console.log("");

            vm.startBroadcast(deployer);
            vault.checkAndTriggerForcedBurn();
            vm.stopBroadcast();

            uint256 pendingBurn = vault.pendingForcedBurn();
            uint256 deadline = vault.forcedBurnDeadline();

            console.log("Forced burn triggered!");
            console.log("Pending burn:", pendingBurn / 1 ether, "tokens");
            console.log("Grace period ends:", deadline);
            console.log(
                "Grace period:",
                (deadline - block.timestamp) / 1 hours,
                "hours"
            );
            console.log("");
        } else {
            console.log("Supply does not exceed cap - forced burn not needed");
            console.log("Skipping Phase 8 (forced burn)");
            console.log("");
        }
    }

    function _phase8_ForcedBurn() internal {
        console.log("=== PHASE 8: Execute Forced Burn ===");
        console.log("");

        uint256 pendingBurn = vault.pendingForcedBurn();
        uint256 deadline = vault.forcedBurnDeadline();

        // Check if forced burn was actually triggered
        if (pendingBurn == 0 || deadline == 0) {
            console.log("No forced burn pending - skipping this phase");
            console.log("(Supply did not exceed cap in Phase 7)");
            console.log("");
            return;
        }

        console.log("Waiting for grace period to end...");
        console.log("Current time:", block.timestamp);
        console.log("Deadline:", deadline);
        console.log("");

        // Fast forward past grace period
        vm.warp(deadline + 1);

        console.log("Grace period ended. Executing forced burn...");
        console.log("");

        (, , uint256 collBefore, uint256 supplyBefore, , , ) = vault
            .getVaultState();

        vm.startBroadcast(deployer);

        // Execute forced burn with max owners to process (100 should be enough for demo)
        vault.executeForcedBurn(100);

        vm.stopBroadcast();

        (, , uint256 collAfter, uint256 supplyAfter, , , ) = vault
            .getVaultState();

        console.log("Forced burn executed!");
        console.log("Tokens burned:", (supplyBefore - supplyAfter) / 1 ether);
        console.log(
            "Collateral written down:",
            (collBefore - collAfter) / 1 ether,
            "CELO"
        );
        console.log("New supply:", supplyAfter / 1 ether, "tokens");
        console.log("New collateral:", collAfter / 1 ether, "CELO");
        console.log("");
        console.log("This demonstrates the forced contraction mechanism");
        console.log("when creator aura drops significantly.");
        console.log("");
    }

    function _phase9_Liquidation() internal {
        console.log("=== PHASE 9: Liquidation Scenario ===");
        console.log("");
        console.log("Simulating critical aura drop to trigger liquidation");
        console.log("");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours + 1);

        vm.startBroadcast(deployer);

        string memory mockIpfsHash = "QmMockCriticalMetrics000";
        oracle.pushAura(address(vault), CRITICAL_AURA, mockIpfsHash);

        vm.stopBroadcast();

        // Check health
        (
            uint256 creatorColl,
            uint256 fanColl,
            uint256 totalColl,
            uint256 supply,
            uint256 peg,
            ,
            uint256 health
        ) = vault.getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("Critical oracle update!");
        console.log("Aura:", aura);
        console.log("Peg:", peg / 1 ether, "CELO");
        console.log("Total collateral:", totalColl / 1 ether, "CELO");
        console.log("Total supply:", supply / 1 ether, "tokens");
        console.log("Health:", health / 1e16, "%");
        console.log("Liquidation threshold:", vault.LIQ_CR() / 1e16, "%");
        console.log("");

        if (health < vault.LIQ_CR()) {
            console.log("Vault is liquidatable! Health below 120%");
            console.log("");

            // Calculate liquidation payment
            uint256 liquidationPayment = 5 ether; // Liquidator injects 5 CELO

            console.log(
                "Liquidator injecting:",
                liquidationPayment / 1 ether,
                "CELO"
            );
            console.log("");

            uint256 liquidatorBalBefore = liquidator.balance;
            uint256 creatorCollBefore = creatorColl;

            // Use private key for Anvil account 4
            vm.startBroadcast(
                0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a
            );
            vault.liquidate{value: liquidationPayment}();
            vm.stopBroadcast();

            uint256 liquidatorBalAfter = liquidator.balance;

            // Log results
            (
                uint256 creatorCollAfter,
                ,
                uint256 totalCollAfter,
                uint256 supplyAfter,
                ,
                ,
                uint256 healthAfter
            ) = vault.getVaultState();

            console.log("Liquidation executed!");
            console.log("Tokens burned:", (supply - supplyAfter) / 1 ether);
            console.log("New supply:", supplyAfter / 1 ether, "tokens");
            console.log("New health:", healthAfter / 1e16, "%");
            console.log(
                "Creator penalty:",
                (creatorCollBefore - creatorCollAfter) / 1 ether,
                "CELO"
            );
            console.log(
                "Liquidator net gain:",
                (liquidatorBalAfter -
                    liquidatorBalBefore +
                    liquidationPayment) / 1 ether,
                "CELO"
            );
            console.log("");
        } else {
            console.log("Vault is still healthy (above liquidation threshold)");
            console.log("Liquidation not possible at this time");
            console.log("");
        }
    }

    function _printFinalSummary() internal view {
        console.log("");
        console.log("========================================");
        console.log("   Demo Complete - Final Summary");
        console.log("========================================");
        console.log("");

        (
            uint256 creatorColl,
            uint256 fanColl,
            uint256 totalColl,
            uint256 supply,
            uint256 peg,
            uint8 stage,
            uint256 health
        ) = vault.getVaultState();
        uint256 aura = vault.getCurrentAura();

        console.log("Vault Address:", address(vault));
        console.log("Token Address:", address(token));
        console.log("");
        console.log("Final State:");
        console.log("  Aura:", aura);
        console.log("  Peg:", peg / 1 ether, "CELO");
        console.log("  Stage:", stage);
        console.log("  Total Supply:", supply / 1 ether, "tokens");
        console.log("  Creator Collateral:", creatorColl / 1 ether, "CELO");
        console.log("  Fan Collateral:", fanColl / 1 ether, "CELO");
        console.log("  Total Collateral:", totalColl / 1 ether, "CELO");
        console.log("  Health:", health / 1e16, "%");
        console.log("");
        console.log("Token Balances:");
        console.log("  Fan1:", token.balanceOf(fan1) / 1 ether, "tokens");
        console.log("  Fan2:", token.balanceOf(fan2) / 1 ether, "tokens");
        console.log("");
        console.log("Demonstrated Features:");
        console.log("  [x] Contract deployment");
        console.log("  [x] Creator bootstrapping");
        console.log("  [x] Oracle integration (mock)");
        console.log("  [x] Fan minting with peg calculation");
        console.log("  [x] Dynamic peg adjustment");
        console.log("  [x] Supply cap enforcement");
        console.log("  [x] Forced burn trigger & execution");
        console.log("  [x] Liquidation mechanism");
        console.log("");
        console.log("For real testnet testing:");
        console.log("  1. Deploy contracts using Deploy.s.sol");
        console.log("  2. Configure oracle/.env.local with API keys");
        console.log("  3. Run oracle.js at each update point");
        console.log("  4. See DEMO.md for detailed instructions");
        console.log("");
        console.log("========================================");
        console.log("");
    }
}
