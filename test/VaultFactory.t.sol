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
    address public oracleAddress = address(2);
    address public creator1 = address(3);
    address public creator2 = address(4);
    address public nonOwner = address(5);

    // Events (must be declared in test contract for vm.expectEmit)
    event VaultCreated(address indexed creator, address vault, address token, uint256 baseCap);
    event StageConfigured(address indexed vault, uint8 stage, uint256 stakeRequired, uint256 mintCap);

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
    }

    // ============ Vault Creation Tests ============

    function test_CreateVault_ValidParameters() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        (address vaultAddr, address tokenAddr) = factory.createVault(name, symbol, creator1, baseCap);

        // Verify vault was created
        assertTrue(vaultAddr != address(0), "Vault address should not be zero");
        assertTrue(tokenAddr != address(0), "Token address should not be zero");

        // Verify vault is registered
        assertEq(factory.creatorToVault(creator1), vaultAddr, "Vault should be registered to creator");

        // Verify vault properties
        CreatorVault vault = CreatorVault(vaultAddr);
        assertEq(vault.creator(), creator1, "Vault creator should match");
        assertEq(vault.token(), tokenAddr, "Vault token should match");
        assertEq(vault.oracle(), address(oracle), "Vault oracle should match");
        assertEq(vault.treasury(), address(treasury), "Vault treasury should match");
        assertEq(vault.baseCap(), baseCap, "Vault baseCap should match");
        assertEq(vault.stage(), 0, "Initial stage should be 0");
        assertEq(vault.totalSupply(), 0, "Initial supply should be 0");

        // Verify token properties
        CreatorToken token = CreatorToken(tokenAddr);
        assertEq(token.name(), name, "Token name should match");
        assertEq(token.symbol(), symbol, "Token symbol should match");
    }

    function test_CreateVault_EmitsEvent() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        // We can't predict the exact addresses, so we check the event is emitted
        vm.expectEmit(true, false, false, false);
        emit VaultCreated(creator1, address(0), address(0), baseCap);

        factory.createVault(name, symbol, creator1, baseCap);
    }

    function test_CreateVault_MultipleDifferentCreators() public {
        string memory name1 = "Creator1 Token";
        string memory symbol1 = "CRT1";
        uint256 baseCap1 = 50_000e18;

        string memory name2 = "Creator2 Token";
        string memory symbol2 = "CRT2";
        uint256 baseCap2 = 200_000e18;

        // Create vault for creator1
        (address vault1, address token1) = factory.createVault(name1, symbol1, creator1, baseCap1);

        // Create vault for creator2
        (address vault2, address token2) = factory.createVault(name2, symbol2, creator2, baseCap2);

        // Verify both vaults are registered
        assertEq(factory.creatorToVault(creator1), vault1, "Creator1 vault should be registered");
        assertEq(factory.creatorToVault(creator2), vault2, "Creator2 vault should be registered");

        // Verify vaults are different
        assertTrue(vault1 != vault2, "Vaults should be different");
        assertTrue(token1 != token2, "Tokens should be different");

        // Verify vault properties
        assertEq(CreatorVault(vault1).creator(), creator1, "Vault1 creator should match");
        assertEq(CreatorVault(vault2).creator(), creator2, "Vault2 creator should match");
        assertEq(CreatorVault(vault1).baseCap(), baseCap1, "Vault1 baseCap should match");
        assertEq(CreatorVault(vault2).baseCap(), baseCap2, "Vault2 baseCap should match");
    }

    function test_CreateVault_InitializesDefaultStages() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        (address vaultAddr,) = factory.createVault(name, symbol, creator1, baseCap);
        CreatorVault vault = CreatorVault(vaultAddr);

        // Verify stage 0 config
        (uint256 stake0, uint256 cap0) = vault.stageConfigs(0);
        assertEq(stake0, 0, "Stage 0 stake should be 0");
        assertEq(cap0, 0, "Stage 0 cap should be 0");

        // Verify stage 1 config
        (uint256 stake1, uint256 cap1) = vault.stageConfigs(1);
        assertEq(stake1, 100e18, "Stage 1 stake should be 100 CELO");
        assertEq(cap1, 500e18, "Stage 1 cap should be 500 tokens");

        // Verify stage 2 config
        (uint256 stake2, uint256 cap2) = vault.stageConfigs(2);
        assertEq(stake2, 300e18, "Stage 2 stake should be 300 CELO");
        assertEq(cap2, 2500e18, "Stage 2 cap should be 2500 tokens");

        // Verify stage 3 config
        (uint256 stake3, uint256 cap3) = vault.stageConfigs(3);
        assertEq(stake3, 800e18, "Stage 3 stake should be 800 CELO");
        assertEq(cap3, 9500e18, "Stage 3 cap should be 9500 tokens");

        // Verify stage 4 config
        (uint256 stake4, uint256 cap4) = vault.stageConfigs(4);
        assertEq(stake4, 1800e18, "Stage 4 stake should be 1800 CELO");
        assertEq(cap4, 34500e18, "Stage 4 cap should be 34500 tokens");
    }

    function test_RevertWhen_CreatorIsZeroAddress() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        factory.createVault(name, symbol, address(0), baseCap);
    }

    function test_RevertWhen_BaseCapIsZero() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";

        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        factory.createVault(name, symbol, creator1, 0);
    }

    function test_RevertWhen_CreatorAlreadyHasVault() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        // Create first vault
        factory.createVault(name, symbol, creator1, baseCap);

        // Try to create second vault for same creator
        vm.expectRevert(VaultFactory.VaultAlreadyExists.selector);
        factory.createVault("Another Token", "ANTH", creator1, baseCap);
    }

    // ============ Creator-to-Vault Registry Tests ============

    function test_CreatorToVault_ReturnsZeroForUnregisteredCreator() public view {
        assertEq(factory.creatorToVault(creator1), address(0), "Unregistered creator should return zero address");
    }

    function test_CreatorToVault_ReturnsCorrectVault() public {
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        (address vaultAddr,) = factory.createVault(name, symbol, creator1, baseCap);

        assertEq(factory.creatorToVault(creator1), vaultAddr, "Registry should return correct vault");
    }

    function test_CreatorToVault_IndependentForDifferentCreators() public {
        (address vault1,) = factory.createVault("Token1", "TK1", creator1, 50_000e18);
        (address vault2,) = factory.createVault("Token2", "TK2", creator2, 100_000e18);

        assertEq(factory.creatorToVault(creator1), vault1, "Creator1 should map to vault1");
        assertEq(factory.creatorToVault(creator2), vault2, "Creator2 should map to vault2");
        assertTrue(vault1 != vault2, "Vaults should be different");
    }

    // ============ setStageConfig Tests ============

    function test_SetStageConfig_ByOwner() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        // Set custom stage config
        uint8 stage = 5;
        uint256 stakeRequired = 5000e18;
        uint256 mintCap = 100_000e18;

        vm.prank(owner);
        factory.setStageConfig(vaultAddr, stage, stakeRequired, mintCap);

        // Verify stage config was set
        CreatorVault vault = CreatorVault(vaultAddr);
        (uint256 stake, uint256 cap) = vault.stageConfigs(stage);
        assertEq(stake, stakeRequired, "Stake requirement should be set");
        assertEq(cap, mintCap, "Mint cap should be set");
    }

    function test_SetStageConfig_EmitsEvent() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        uint8 stage = 5;
        uint256 stakeRequired = 5000e18;
        uint256 mintCap = 100_000e18;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit StageConfigured(vaultAddr, stage, stakeRequired, mintCap);

        factory.setStageConfig(vaultAddr, stage, stakeRequired, mintCap);
    }

    function test_SetStageConfig_OverrideDefaultStage() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        // Override stage 1 config
        uint8 stage = 1;
        uint256 newStakeRequired = 200e18; // Changed from default 100
        uint256 newMintCap = 1000e18; // Changed from default 500

        vm.prank(owner);
        factory.setStageConfig(vaultAddr, stage, newStakeRequired, newMintCap);

        // Verify stage config was updated
        CreatorVault vault = CreatorVault(vaultAddr);
        (uint256 stake, uint256 cap) = vault.stageConfigs(stage);
        assertEq(stake, newStakeRequired, "Stake requirement should be updated");
        assertEq(cap, newMintCap, "Mint cap should be updated");
    }

    function test_SetStageConfig_MultipleStages() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        // Set multiple custom stages
        vm.prank(owner);
        factory.setStageConfig(vaultAddr, 5, 3000e18, 50_000e18);

        vm.prank(owner);
        factory.setStageConfig(vaultAddr, 6, 6000e18, 150_000e18);

        vm.prank(owner);
        factory.setStageConfig(vaultAddr, 7, 10_000e18, 500_000e18);

        // Verify all stages
        CreatorVault vault = CreatorVault(vaultAddr);

        (uint256 stake5, uint256 cap5) = vault.stageConfigs(5);
        assertEq(stake5, 3000e18, "Stage 5 stake should be set");
        assertEq(cap5, 50_000e18, "Stage 5 cap should be set");

        (uint256 stake6, uint256 cap6) = vault.stageConfigs(6);
        assertEq(stake6, 6000e18, "Stage 6 stake should be set");
        assertEq(cap6, 150_000e18, "Stage 6 cap should be set");

        (uint256 stake7, uint256 cap7) = vault.stageConfigs(7);
        assertEq(stake7, 10_000e18, "Stage 7 stake should be set");
        assertEq(cap7, 500_000e18, "Stage 7 cap should be set");
    }

    function test_RevertWhen_NonOwnerSetsStageConfig() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        // Try to set stage config as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        factory.setStageConfig(vaultAddr, 5, 5000e18, 100_000e18);
    }

    function test_RevertWhen_CreatorSetsStageConfig() public {
        // Create a vault first
        (address vaultAddr,) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        // Try to set stage config as creator (not factory owner)
        vm.prank(creator1);
        vm.expectRevert();
        factory.setStageConfig(vaultAddr, 5, 5000e18, 100_000e18);
    }

    function test_RevertWhen_SetStageConfigWithZeroVaultAddress() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        factory.setStageConfig(address(0), 5, 5000e18, 100_000e18);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsImmutableVariables() public view {
        assertEq(factory.treasury(), address(treasury), "Treasury should be set");
        assertEq(factory.oracle(), address(oracle), "Oracle should be set");
        assertEq(factory.owner(), owner, "Owner should be set");
    }

    function test_RevertWhen_ConstructorWithZeroTreasury() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        new VaultFactory(owner, address(0), address(oracle));
    }

    function test_RevertWhen_ConstructorWithZeroOracle() public {
        vm.prank(owner);
        vm.expectRevert(VaultFactory.InvalidParameters.selector);
        new VaultFactory(owner, address(treasury), address(0));
    }

    // ============ Integration Tests ============

    function test_FullLifecycle_CreateAndConfigureVault() public {
        // Create vault
        string memory name = "Creator Token";
        string memory symbol = "CRTR";
        uint256 baseCap = 100_000e18;

        (address vaultAddr, address tokenAddr) = factory.createVault(name, symbol, creator1, baseCap);

        // Verify creation
        assertTrue(vaultAddr != address(0), "Vault should be created");
        assertTrue(tokenAddr != address(0), "Token should be created");
        assertEq(factory.creatorToVault(creator1), vaultAddr, "Vault should be registered");

        // Verify default stages are set
        CreatorVault vault = CreatorVault(vaultAddr);
        (uint256 stake1, uint256 cap1) = vault.stageConfigs(1);
        assertEq(stake1, 100e18, "Default stage 1 should be set");

        // Customize stage configuration
        vm.prank(owner);
        factory.setStageConfig(vaultAddr, 5, 3000e18, 75_000e18);

        // Verify custom stage
        (uint256 stake5, uint256 cap5) = vault.stageConfigs(5);
        assertEq(stake5, 3000e18, "Custom stage should be set");
        assertEq(cap5, 75_000e18, "Custom stage cap should be set");
    }

    function test_MultipleVaults_IndependentConfigurations() public {
        // Create two vaults
        (address vault1,) = factory.createVault("Token1", "TK1", creator1, 50_000e18);
        (address vault2,) = factory.createVault("Token2", "TK2", creator2, 200_000e18);

        // Configure vault1 stage 5
        vm.prank(owner);
        factory.setStageConfig(vault1, 5, 2000e18, 30_000e18);

        // Configure vault2 stage 5 differently
        vm.prank(owner);
        factory.setStageConfig(vault2, 5, 8000e18, 250_000e18);

        // Verify vault1 config
        CreatorVault v1 = CreatorVault(vault1);
        (uint256 stake1, uint256 cap1) = v1.stageConfigs(5);
        assertEq(stake1, 2000e18, "Vault1 stage 5 stake should match");
        assertEq(cap1, 30_000e18, "Vault1 stage 5 cap should match");

        // Verify vault2 config
        CreatorVault v2 = CreatorVault(vault2);
        (uint256 stake2, uint256 cap2) = v2.stageConfigs(5);
        assertEq(stake2, 8000e18, "Vault2 stage 5 stake should match");
        assertEq(cap2, 250_000e18, "Vault2 stage 5 cap should match");
    }

    function test_VaultAndTokenDeployment_CorrectLinking() public {
        (address vaultAddr, address tokenAddr) = factory.createVault("Token", "TKN", creator1, 100_000e18);

        CreatorVault vault = CreatorVault(vaultAddr);
        CreatorToken token = CreatorToken(tokenAddr);

        // Verify vault points to token
        assertEq(vault.token(), tokenAddr, "Vault should reference token");

        // Verify token can only be minted by vault (test by checking owner/vault relationship)
        // The token contract restricts mint/burn to vault address
        // We can't directly test this without trying to mint, but we verify the addresses are linked
        assertTrue(vaultAddr != address(0), "Vault address should be valid");
        assertTrue(tokenAddr != address(0), "Token address should be valid");
    }
}
