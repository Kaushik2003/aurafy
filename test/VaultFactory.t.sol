// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {VaultFactory} from "../contracts/VaultFactory.sol";
import {CreatorVault} from "../contracts/CreatorVault.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";
import {Treasury} from "../contracts/Treasury.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

contract VaultFactoryTest is Test {
    VaultFactory public factory;
    Treasury public treasury;
    AuraOracle public oracle;

    address public owner = address(1);
    address public creator = address(2);
    address public oracleAddress = address(3);

    // Events (must be declared in test contract for vm.expectEmit)
    event VaultCreated(address indexed creator, address vault, address token, uint256 baseCap);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy Treasury
        treasury = new Treasury(owner);

        // Deploy AuraOracle
        oracle = new AuraOracle(owner, oracleAddress);

        // Deploy VaultFactory
        factory = new VaultFactory(owner, address(treasury), address(oracle));

        vm.stopPrank();
    }

    function test_CreateVault() public {
        vm.prank(owner);
        (address vaultAddr, address tokenAddr) = factory.createVault("Test Creator Token", "TCT", creator, 100_000e18);

        // Verify vault was created
        assertTrue(vaultAddr != address(0), "Vault address should not be zero");
        assertTrue(tokenAddr != address(0), "Token address should not be zero");

        // Verify registry
        assertEq(factory.creatorToVault(creator), vaultAddr, "Creator should be mapped to vault");

        // Verify vault properties
        CreatorVault vault = CreatorVault(vaultAddr);
        assertEq(vault.creator(), creator, "Vault creator should match");
        assertEq(vault.token(), tokenAddr, "Vault token should match");
        assertEq(vault.baseCap(), 100_000e18, "Vault baseCap should match");
        assertEq(vault.stage(), 0, "Initial stage should be 0");

        // Verify token properties
        CreatorToken token = CreatorToken(tokenAddr);
        assertEq(token.name(), "Test Creator Token", "Token name should match");
        assertEq(token.symbol(), "TCT", "Token symbol should match");
        assertEq(token.vault(), vaultAddr, "Token vault should match");
    }

    function test_CreateVault_DefaultStageConfigs() public {
        vm.prank(owner);
        (address vaultAddr,) = factory.createVault("Test Creator Token", "TCT", creator, 100_000e18);

        CreatorVault vault = CreatorVault(vaultAddr);

        // Check stage 0 config
        (uint256 stake0, uint256 cap0) = vault.stageConfigs(0);
        assertEq(stake0, 0, "Stage 0 stake should be 0");
        assertEq(cap0, 0, "Stage 0 cap should be 0");

        // Check stage 1 config
        (uint256 stake1, uint256 cap1) = vault.stageConfigs(1);
        assertEq(stake1, 100e18, "Stage 1 stake should be 100 CELO");
        assertEq(cap1, 500e18, "Stage 1 cap should be 500 tokens");

        // Check stage 2 config
        (uint256 stake2, uint256 cap2) = vault.stageConfigs(2);
        assertEq(stake2, 300e18, "Stage 2 stake should be 300 CELO");
        assertEq(cap2, 2500e18, "Stage 2 cap should be 2500 tokens");
    }

    function test_RevertWhen_CreatorAlreadyHasVault() public {
        vm.startPrank(owner);

        // Create first vault
        factory.createVault("Test Token 1", "TT1", creator, 100_000e18);

        // Try to create second vault for same creator
        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.createVault("Test Token 2", "TT2", creator, 100_000e18);

        vm.stopPrank();
    }

    function test_RevertWhen_InvalidParameters() public {
        vm.startPrank(owner);

        // Test with zero creator address
        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        factory.createVault("Test Token", "TT", address(0), 100_000e18);

        // Test with zero baseCap
        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        factory.createVault("Test Token", "TT", creator, 0);

        vm.stopPrank();
    }

    function test_SetStageConfig() public {
        vm.startPrank(owner);

        // Create vault
        (address vaultAddr,) = factory.createVault("Test Creator Token", "TCT", creator, 100_000e18);

        // Set custom stage config
        factory.setStageConfig(vaultAddr, 5, 5000e18, 100_000e18);

        // Verify config was set
        CreatorVault vault = CreatorVault(vaultAddr);
        (uint256 stake, uint256 cap) = vault.stageConfigs(5);
        assertEq(stake, 5000e18, "Stage 5 stake should be 5000 CELO");
        assertEq(cap, 100_000e18, "Stage 5 cap should be 100000 tokens");

        vm.stopPrank();
    }

    function test_RevertWhen_NonOwnerSetsStageConfig() public {
        vm.prank(owner);
        (address vaultAddr,) = factory.createVault("Test Creator Token", "TCT", creator, 100_000e18);

        // Try to set stage config as non-owner
        vm.prank(creator);
        vm.expectRevert();
        factory.setStageConfig(vaultAddr, 5, 5000e18, 100_000e18);
    }

    function test_EmitVaultCreatedEvent() public {
        vm.prank(owner);

        // We only check the indexed creator parameter (first true)
        // The vault and token addresses are not indexed and will be actual addresses
        vm.expectEmit(true, false, false, false);
        emit VaultCreated(creator, address(0), address(0), 100_000e18);

        factory.createVault("Test Creator Token", "TCT", creator, 100_000e18);
    }
}
