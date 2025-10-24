// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {AuraOracle} from "../contracts/AuraOracle.sol";

contract AuraOracleTest is Test {
    AuraOracle public oracle;

    address public owner = address(1);
    address public oracleAddress = address(2);
    address public vault1 = address(3);
    address public vault2 = address(4);
    address public unauthorized = address(5);

    // Events (must be declared in test contract for vm.expectEmit)
    event AuraUpdated(address indexed vault, uint256 aura, string ipfsHash, uint256 timestamp);
    event OracleAddressUpdated(address indexed oldOracle, address indexed newOracle);

    function setUp() public {
        vm.prank(owner);
        oracle = new AuraOracle(owner, oracleAddress);
    }

    // ============ pushAura Tests ============

    function test_PushAura_ValidParameters() public {
        uint256 auraValue = 100;
        string memory ipfsHash = "QmTest123";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue, ipfsHash);

        assertEq(oracle.getAura(vault1), auraValue, "Aura should be stored correctly");
        assertEq(oracle.getIpfsHash(vault1), ipfsHash, "IPFS hash should be stored correctly");
        assertEq(oracle.getLastUpdateTimestamp(vault1), block.timestamp, "Timestamp should be current block");
    }

    function test_PushAura_ZeroAura() public {
        uint256 auraValue = 0;
        string memory ipfsHash = "QmZeroAura";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue, ipfsHash);

        assertEq(oracle.getAura(vault1), auraValue, "Zero aura should be stored");
    }

    function test_PushAura_MaxAura() public {
        uint256 auraValue = 200;
        string memory ipfsHash = "QmMaxAura";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue, ipfsHash);

        assertEq(oracle.getAura(vault1), auraValue, "Max aura should be stored");
    }

    function test_PushAura_EmptyIpfsHash() public {
        uint256 auraValue = 50;
        string memory ipfsHash = "";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue, ipfsHash);

        assertEq(oracle.getIpfsHash(vault1), ipfsHash, "Empty IPFS hash should be stored");
    }

    function test_PushAura_UpdatesExistingValue() public {
        // First update
        uint256 auraValue1 = 80;
        string memory ipfsHash1 = "QmFirst";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue1, ipfsHash1);

        assertEq(oracle.getAura(vault1), auraValue1, "First aura should be stored");

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours + 1);

        // Second update
        uint256 auraValue2 = 120;
        string memory ipfsHash2 = "QmSecond";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue2, ipfsHash2);

        assertEq(oracle.getAura(vault1), auraValue2, "Aura should be updated");
        assertEq(oracle.getIpfsHash(vault1), ipfsHash2, "IPFS hash should be updated");
    }

    function test_PushAura_MultipleDifferentVaults() public {
        uint256 aura1 = 75;
        uint256 aura2 = 150;
        string memory ipfs1 = "QmVault1";
        string memory ipfs2 = "QmVault2";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, aura1, ipfs1);

        vm.prank(oracleAddress);
        oracle.pushAura(vault2, aura2, ipfs2);

        assertEq(oracle.getAura(vault1), aura1, "Vault1 aura should be stored");
        assertEq(oracle.getAura(vault2), aura2, "Vault2 aura should be stored");
        assertEq(oracle.getIpfsHash(vault1), ipfs1, "Vault1 IPFS hash should be stored");
        assertEq(oracle.getIpfsHash(vault2), ipfs2, "Vault2 IPFS hash should be stored");
    }

    function test_PushAura_EmitsEvent() public {
        uint256 auraValue = 90;
        string memory ipfsHash = "QmEventTest";

        vm.prank(oracleAddress);
        vm.expectEmit(true, false, false, true);
        emit AuraUpdated(vault1, auraValue, ipfsHash, block.timestamp);

        oracle.pushAura(vault1, auraValue, ipfsHash);
    }

    // ============ Cooldown Enforcement Tests ============

    function test_RevertWhen_CooldownNotElapsed() public {
        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmFirst");

        // Try to update immediately (should revert)
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.CooldownNotElapsed.selector);
        oracle.pushAura(vault1, 110, "QmSecond");
    }

    function test_RevertWhen_CooldownNotElapsed_OneSecondBefore() public {
        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmFirst");

        // Wait almost 6 hours (1 second short)
        vm.warp(block.timestamp + 6 hours - 1);

        // Try to update (should revert)
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.CooldownNotElapsed.selector);
        oracle.pushAura(vault1, 110, "QmSecond");
    }

    function test_PushAura_AfterExactCooldown() public {
        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmFirst");

        // Wait exactly 6 hours
        vm.warp(block.timestamp + 6 hours);

        // Second update (should succeed)
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 110, "QmSecond");

        assertEq(oracle.getAura(vault1), 110, "Aura should be updated after cooldown");
    }

    function test_PushAura_AfterLongDelay() public {
        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmFirst");

        // Wait much longer than cooldown
        vm.warp(block.timestamp + 24 hours);

        // Second update (should succeed)
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 110, "QmSecond");

        assertEq(oracle.getAura(vault1), 110, "Aura should be updated after long delay");
    }

    function test_PushAura_FirstUpdateNoCooldown() public {
        // First update should not check cooldown
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmFirst");

        assertEq(oracle.getAura(vault1), 100, "First update should succeed without cooldown");
    }

    function test_PushAura_CooldownPerVault() public {
        // Update vault1
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmVault1First");

        // Immediately update vault2 (should succeed - different vault)
        vm.prank(oracleAddress);
        oracle.pushAura(vault2, 150, "QmVault2First");

        assertEq(oracle.getAura(vault1), 100, "Vault1 aura should be stored");
        assertEq(oracle.getAura(vault2), 150, "Vault2 aura should be stored");

        // Try to update vault1 again immediately (should revert)
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.CooldownNotElapsed.selector);
        oracle.pushAura(vault1, 110, "QmVault1Second");
    }

    // ============ Authorization Tests ============

    function test_RevertWhen_UnauthorizedCallerPushesAura() public {
        vm.prank(unauthorized);
        vm.expectRevert(AuraOracle.Unauthorized.selector);
        oracle.pushAura(vault1, 100, "QmUnauthorized");
    }

    function test_RevertWhen_OwnerPushesAura() public {
        // Owner is not oracle, so should revert
        vm.prank(owner);
        vm.expectRevert(AuraOracle.Unauthorized.selector);
        oracle.pushAura(vault1, 100, "QmOwner");
    }

    function test_RevertWhen_VaultPushesAura() public {
        // Vault cannot push its own aura
        vm.prank(vault1);
        vm.expectRevert(AuraOracle.Unauthorized.selector);
        oracle.pushAura(vault1, 100, "QmSelf");
    }

    // ============ getAura Tests ============

    function test_GetAura_ReturnsZeroForUnsetVault() public view {
        assertEq(oracle.getAura(vault1), 0, "Unset vault should return 0 aura");
    }

    function test_GetAura_ReturnsCorrectValue() public {
        uint256 auraValue = 125;

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, auraValue, "QmTest");

        assertEq(oracle.getAura(vault1), auraValue, "getAura should return stored value");
    }

    function test_GetAura_AfterMultipleUpdates() public {
        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 80, "QmFirst");

        // Wait and second update
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 140, "QmSecond");

        assertEq(oracle.getAura(vault1), 140, "getAura should return latest value");
    }

    // ============ IPFS Hash Storage and Retrieval Tests ============

    function test_GetIpfsHash_ReturnsEmptyForUnsetVault() public view {
        assertEq(oracle.getIpfsHash(vault1), "", "Unset vault should return empty IPFS hash");
    }

    function test_GetIpfsHash_ReturnsCorrectValue() public {
        string memory ipfsHash = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, ipfsHash);

        assertEq(oracle.getIpfsHash(vault1), ipfsHash, "getIpfsHash should return stored value");
    }

    function test_GetIpfsHash_AfterMultipleUpdates() public {
        string memory ipfs1 = "QmFirst";
        string memory ipfs2 = "QmSecond";

        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 80, ipfs1);

        // Wait and second update
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 140, ipfs2);

        assertEq(oracle.getIpfsHash(vault1), ipfs2, "getIpfsHash should return latest value");
    }

    function test_GetIpfsHash_LongHash() public {
        string memory longHash = "QmYwAPJzv5CZsnA625s3Xf2nemtYgPpHdWEz79ojWnPbdG/metadata.json";

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, longHash);

        assertEq(oracle.getIpfsHash(vault1), longHash, "Long IPFS hash should be stored correctly");
    }

    // ============ Timestamp Tests ============

    function test_GetLastUpdateTimestamp_ReturnsZeroForUnsetVault() public view {
        assertEq(oracle.getLastUpdateTimestamp(vault1), 0, "Unset vault should return 0 timestamp");
    }

    function test_GetLastUpdateTimestamp_ReturnsCorrectValue() public {
        uint256 updateTime = block.timestamp;

        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmTest");

        assertEq(oracle.getLastUpdateTimestamp(vault1), updateTime, "Timestamp should match update time");
    }

    function test_GetLastUpdateTimestamp_UpdatesOnEachPush() public {
        // First update
        uint256 time1 = block.timestamp;
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 80, "QmFirst");

        assertEq(oracle.getLastUpdateTimestamp(vault1), time1, "First timestamp should be stored");

        // Wait and second update
        vm.warp(block.timestamp + 6 hours);
        uint256 time2 = block.timestamp;
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 140, "QmSecond");

        assertEq(oracle.getLastUpdateTimestamp(vault1), time2, "Timestamp should update");
    }

    // ============ Oracle Address Management Tests ============

    function test_SetOracleAddress_ByOwner() public {
        address newOracle = address(99);

        vm.prank(owner);
        oracle.setOracleAddress(newOracle);

        assertEq(oracle.oracleAddress(), newOracle, "Oracle address should be updated");
    }

    function test_SetOracleAddress_EmitsEvent() public {
        address newOracle = address(99);

        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit OracleAddressUpdated(oracleAddress, newOracle);

        oracle.setOracleAddress(newOracle);
    }

    function test_SetOracleAddress_AllowsNewOracleToPush() public {
        address newOracle = address(99);

        // Change oracle address
        vm.prank(owner);
        oracle.setOracleAddress(newOracle);

        // New oracle should be able to push
        vm.prank(newOracle);
        oracle.pushAura(vault1, 100, "QmNewOracle");

        assertEq(oracle.getAura(vault1), 100, "New oracle should be able to push aura");
    }

    function test_SetOracleAddress_PreventsOldOracleFromPushing() public {
        address newOracle = address(99);

        // Change oracle address
        vm.prank(owner);
        oracle.setOracleAddress(newOracle);

        // Old oracle should not be able to push
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.Unauthorized.selector);
        oracle.pushAura(vault1, 100, "QmOldOracle");
    }

    function test_RevertWhen_NonOwnerSetsOracleAddress() public {
        address newOracle = address(99);

        vm.prank(unauthorized);
        vm.expectRevert();
        oracle.setOracleAddress(newOracle);
    }

    // ============ Integration Tests ============

    function test_FullLifecycle_SingleVault() public {
        // Initial state
        assertEq(oracle.getAura(vault1), 0, "Initial aura should be 0");
        assertEq(oracle.getIpfsHash(vault1), "", "Initial IPFS hash should be empty");

        // First update
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 50, "QmInitial");

        assertEq(oracle.getAura(vault1), 50, "Aura after first update");

        // Wait and second update
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmGrowth");

        assertEq(oracle.getAura(vault1), 100, "Aura after growth");

        // Wait and third update (decline)
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 75, "QmDecline");

        assertEq(oracle.getAura(vault1), 75, "Aura after decline");
        assertEq(oracle.getIpfsHash(vault1), "QmDecline", "Latest IPFS hash");
    }

    function test_MultipleVaults_IndependentCooldowns() public {
        // Update vault1
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 100, "QmVault1");

        // Wait 3 hours
        vm.warp(block.timestamp + 3 hours);

        // Update vault2 (should succeed - independent cooldown)
        vm.prank(oracleAddress);
        oracle.pushAura(vault2, 150, "QmVault2");

        // Wait another 3 hours (total 6 hours from vault1 update)
        vm.warp(block.timestamp + 3 hours);

        // Update vault1 again (should succeed - 6 hours elapsed)
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 110, "QmVault1Update");

        // Try to update vault2 (should revert - only 3 hours elapsed)
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.CooldownNotElapsed.selector);
        oracle.pushAura(vault2, 160, "QmVault2Update");

        assertEq(oracle.getAura(vault1), 110, "Vault1 should be updated");
        assertEq(oracle.getAura(vault2), 150, "Vault2 should not be updated");
    }

    function test_OracleRotation_MidLifecycle() public {
        address newOracle = address(99);

        // Old oracle pushes initial aura
        vm.prank(oracleAddress);
        oracle.pushAura(vault1, 80, "QmOldOracle");

        // Owner rotates oracle
        vm.prank(owner);
        oracle.setOracleAddress(newOracle);

        // Wait for cooldown
        vm.warp(block.timestamp + 6 hours);

        // New oracle pushes update
        vm.prank(newOracle);
        oracle.pushAura(vault1, 120, "QmNewOracle");

        assertEq(oracle.getAura(vault1), 120, "New oracle should be able to update");

        // Old oracle cannot push anymore
        vm.warp(block.timestamp + 6 hours);
        vm.prank(oracleAddress);
        vm.expectRevert(AuraOracle.Unauthorized.selector);
        oracle.pushAura(vault1, 130, "QmOldOracleFail");
    }
}
