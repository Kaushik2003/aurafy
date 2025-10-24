// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {CreatorToken} from "../contracts/CreatorToken.sol";

contract CreatorTokenTest is Test {
    CreatorToken public token;

    address public vault = address(1);
    address public user1 = address(2);
    address public user2 = address(3);
    address public unauthorized = address(4);

    string constant TOKEN_NAME = "Creator Token";
    string constant TOKEN_SYMBOL = "CRTR";

    function setUp() public {
        token = new CreatorToken(TOKEN_NAME, TOKEN_SYMBOL, vault);
    }

    // ============ Constructor Tests ============

    function test_Constructor_SetsNameAndSymbol() public view {
        assertEq(token.name(), TOKEN_NAME, "Token name should be set correctly");
        assertEq(token.symbol(), TOKEN_SYMBOL, "Token symbol should be set correctly");
    }

    function test_Constructor_SetsVaultAddress() public view {
        assertEq(token.vault(), vault, "Vault address should be set correctly");
    }

    function test_Constructor_InitialSupplyIsZero() public view {
        assertEq(token.totalSupply(), 0, "Initial total supply should be 0");
    }

    // ============ Mint Tests - Authorized (Vault) ============

    function test_Mint_ByVault() public {
        uint256 mintAmount = 1000 ether;

        vm.prank(vault);
        token.mint(user1, mintAmount);

        assertEq(token.balanceOf(user1), mintAmount, "User1 should receive minted tokens");
        assertEq(token.totalSupply(), mintAmount, "Total supply should increase");
    }

    function test_Mint_MultipleRecipients() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;

        vm.startPrank(vault);
        token.mint(user1, amount1);
        token.mint(user2, amount2);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount1, "User1 should have correct balance");
        assertEq(token.balanceOf(user2), amount2, "User2 should have correct balance");
        assertEq(token.totalSupply(), amount1 + amount2, "Total supply should be sum of mints");
    }

    function test_Mint_MultipleTimes_SameRecipient() public {
        uint256 mint1 = 100 ether;
        uint256 mint2 = 200 ether;
        uint256 mint3 = 50 ether;

        vm.startPrank(vault);
        token.mint(user1, mint1);
        token.mint(user1, mint2);
        token.mint(user1, mint3);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), mint1 + mint2 + mint3, "User1 balance should accumulate");
        assertEq(token.totalSupply(), mint1 + mint2 + mint3, "Total supply should accumulate");
    }

    function test_Mint_ZeroAmount() public {
        vm.prank(vault);
        token.mint(user1, 0);

        assertEq(token.balanceOf(user1), 0, "Balance should remain 0");
        assertEq(token.totalSupply(), 0, "Total supply should remain 0");
    }

    // ============ Mint Tests - Unauthorized ============

    function test_RevertWhen_UnauthorizedMint() public {
        uint256 mintAmount = 1000 ether;

        vm.prank(unauthorized);
        vm.expectRevert(CreatorToken.Unauthorized.selector);
        token.mint(user1, mintAmount);
    }

    function test_RevertWhen_UserMints() public {
        uint256 mintAmount = 1000 ether;

        vm.prank(user1);
        vm.expectRevert(CreatorToken.Unauthorized.selector);
        token.mint(user1, mintAmount);
    }

    function test_RevertWhen_RecipientMints() public {
        uint256 mintAmount = 1000 ether;

        vm.prank(user2);
        vm.expectRevert(CreatorToken.Unauthorized.selector);
        token.mint(user2, mintAmount);
    }

    // ============ Burn Tests - Authorized (Vault) ============

    function test_Burn_ByVault() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 400 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Burn
        vm.prank(vault);
        token.burn(user1, burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - burnAmount, "User1 balance should decrease");
        assertEq(token.totalSupply(), mintAmount - burnAmount, "Total supply should decrease");
    }

    function test_Burn_FullBalance() public {
        uint256 mintAmount = 1000 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Burn all
        vm.prank(vault);
        token.burn(user1, mintAmount);

        assertEq(token.balanceOf(user1), 0, "User1 balance should be 0");
        assertEq(token.totalSupply(), 0, "Total supply should be 0");
    }

    function test_Burn_MultipleTimes() public {
        uint256 mintAmount = 1000 ether;
        uint256 burn1 = 200 ether;
        uint256 burn2 = 300 ether;
        uint256 burn3 = 100 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Multiple burns
        vm.startPrank(vault);
        token.burn(user1, burn1);
        token.burn(user1, burn2);
        token.burn(user1, burn3);
        vm.stopPrank();

        assertEq(
            token.balanceOf(user1),
            mintAmount - burn1 - burn2 - burn3,
            "User1 balance should reflect all burns"
        );
        assertEq(token.totalSupply(), mintAmount - burn1 - burn2 - burn3, "Total supply should reflect all burns");
    }

    function test_Burn_FromMultipleUsers() public {
        uint256 amount1 = 500 ether;
        uint256 amount2 = 300 ether;
        uint256 burn1 = 200 ether;
        uint256 burn2 = 100 ether;

        // Mint to both users
        vm.startPrank(vault);
        token.mint(user1, amount1);
        token.mint(user2, amount2);

        // Burn from both
        token.burn(user1, burn1);
        token.burn(user2, burn2);
        vm.stopPrank();

        assertEq(token.balanceOf(user1), amount1 - burn1, "User1 balance should decrease");
        assertEq(token.balanceOf(user2), amount2 - burn2, "User2 balance should decrease");
        assertEq(token.totalSupply(), amount1 + amount2 - burn1 - burn2, "Total supply should reflect all operations");
    }

    function test_Burn_ZeroAmount() public {
        uint256 mintAmount = 1000 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Burn zero
        vm.prank(vault);
        token.burn(user1, 0);

        assertEq(token.balanceOf(user1), mintAmount, "Balance should remain unchanged");
        assertEq(token.totalSupply(), mintAmount, "Total supply should remain unchanged");
    }

    // ============ Burn Tests - Unauthorized ============

    function test_RevertWhen_UnauthorizedBurn() public {
        uint256 mintAmount = 1000 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Try to burn as unauthorized
        vm.prank(unauthorized);
        vm.expectRevert(CreatorToken.Unauthorized.selector);
        token.burn(user1, 100 ether);
    }

    function test_RevertWhen_UserBurnsOwnTokens() public {
        uint256 mintAmount = 1000 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User tries to burn their own tokens
        vm.prank(user1);
        vm.expectRevert(CreatorToken.Unauthorized.selector);
        token.burn(user1, 100 ether);
    }

    function test_RevertWhen_BurnExceedsBalance() public {
        uint256 mintAmount = 1000 ether;
        uint256 burnAmount = 1500 ether;

        // Mint first
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Try to burn more than balance
        vm.prank(vault);
        vm.expectRevert();
        token.burn(user1, burnAmount);
    }

    // ============ Standard ERC20 Tests - Transfer ============

    function test_Transfer_BetweenUsers() public {
        uint256 mintAmount = 1000 ether;
        uint256 transferAmount = 300 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 transfers to user2
        vm.prank(user1);
        bool success = token.transfer(user2, transferAmount);

        assertTrue(success, "Transfer should succeed");
        assertEq(token.balanceOf(user1), mintAmount - transferAmount, "User1 balance should decrease");
        assertEq(token.balanceOf(user2), transferAmount, "User2 should receive tokens");
        assertEq(token.totalSupply(), mintAmount, "Total supply should remain unchanged");
    }

    function test_Transfer_FullBalance() public {
        uint256 mintAmount = 1000 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 transfers all to user2
        vm.prank(user1);
        token.transfer(user2, mintAmount);

        assertEq(token.balanceOf(user1), 0, "User1 balance should be 0");
        assertEq(token.balanceOf(user2), mintAmount, "User2 should receive all tokens");
    }

    function test_Transfer_ZeroAmount() public {
        uint256 mintAmount = 1000 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Transfer zero
        vm.prank(user1);
        bool success = token.transfer(user2, 0);

        assertTrue(success, "Zero transfer should succeed");
        assertEq(token.balanceOf(user1), mintAmount, "User1 balance should remain unchanged");
        assertEq(token.balanceOf(user2), 0, "User2 balance should remain 0");
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        uint256 mintAmount = 1000 ether;
        uint256 transferAmount = 1500 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // Try to transfer more than balance
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, transferAmount);
    }

    function test_RevertWhen_TransferFromZeroBalance() public {
        // Try to transfer with no balance
        vm.prank(user1);
        vm.expectRevert();
        token.transfer(user2, 100 ether);
    }

    // ============ Standard ERC20 Tests - Approve ============

    function test_Approve_Spender() public {
        uint256 approvalAmount = 500 ether;

        vm.prank(user1);
        bool success = token.approve(user2, approvalAmount);

        assertTrue(success, "Approval should succeed");
        assertEq(token.allowance(user1, user2), approvalAmount, "Allowance should be set");
    }

    function test_Approve_ZeroAmount() public {
        vm.prank(user1);
        bool success = token.approve(user2, 0);

        assertTrue(success, "Zero approval should succeed");
        assertEq(token.allowance(user1, user2), 0, "Allowance should be 0");
    }

    function test_Approve_UpdateAllowance() public {
        uint256 approval1 = 500 ether;
        uint256 approval2 = 1000 ether;

        vm.startPrank(user1);
        token.approve(user2, approval1);
        assertEq(token.allowance(user1, user2), approval1, "First allowance should be set");

        token.approve(user2, approval2);
        assertEq(token.allowance(user1, user2), approval2, "Allowance should be updated");
        vm.stopPrank();
    }

    // ============ Standard ERC20 Tests - TransferFrom ============

    function test_TransferFrom_WithApproval() public {
        uint256 mintAmount = 1000 ether;
        uint256 approvalAmount = 500 ether;
        uint256 transferAmount = 300 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, approvalAmount);

        // User2 transfers from user1 to unauthorized
        vm.prank(user2);
        bool success = token.transferFrom(user1, unauthorized, transferAmount);

        assertTrue(success, "TransferFrom should succeed");
        assertEq(token.balanceOf(user1), mintAmount - transferAmount, "User1 balance should decrease");
        assertEq(token.balanceOf(unauthorized), transferAmount, "Recipient should receive tokens");
        assertEq(
            token.allowance(user1, user2), approvalAmount - transferAmount, "Allowance should decrease"
        );
    }

    function test_TransferFrom_FullAllowance() public {
        uint256 mintAmount = 1000 ether;
        uint256 approvalAmount = 500 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, approvalAmount);

        // User2 transfers full allowance
        vm.prank(user2);
        token.transferFrom(user1, unauthorized, approvalAmount);

        assertEq(token.balanceOf(user1), mintAmount - approvalAmount, "User1 balance should decrease");
        assertEq(token.balanceOf(unauthorized), approvalAmount, "Recipient should receive tokens");
        assertEq(token.allowance(user1, user2), 0, "Allowance should be 0");
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        uint256 mintAmount = 1000 ether;
        uint256 approvalAmount = 500 ether;
        uint256 transferAmount = 600 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, approvalAmount);

        // User2 tries to transfer more than allowance
        vm.prank(user2);
        vm.expectRevert();
        token.transferFrom(user1, unauthorized, transferAmount);
    }

    function test_RevertWhen_TransferFromWithoutApproval() public {
        uint256 mintAmount = 1000 ether;
        uint256 transferAmount = 300 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User2 tries to transfer without approval
        vm.prank(user2);
        vm.expectRevert();
        token.transferFrom(user1, unauthorized, transferAmount);
    }

    function test_RevertWhen_TransferFromExceedsBalance() public {
        uint256 mintAmount = 500 ether;
        uint256 approvalAmount = 1000 ether;
        uint256 transferAmount = 600 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 approves user2 for more than balance
        vm.prank(user1);
        token.approve(user2, approvalAmount);

        // User2 tries to transfer more than balance
        vm.prank(user2);
        vm.expectRevert();
        token.transferFrom(user1, unauthorized, transferAmount);
    }

    // ============ Integration Tests ============

    function test_MintTransferBurn_Lifecycle() public {
        uint256 mintAmount = 1000 ether;
        uint256 transferAmount = 300 ether;
        uint256 burnAmount = 200 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 transfers to user2
        vm.prank(user1);
        token.transfer(user2, transferAmount);

        // Vault burns from user1
        vm.prank(vault);
        token.burn(user1, burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - transferAmount - burnAmount, "User1 final balance");
        assertEq(token.balanceOf(user2), transferAmount, "User2 final balance");
        assertEq(token.totalSupply(), mintAmount - burnAmount, "Final total supply");
    }

    function test_ApproveTransferFromBurn_Lifecycle() public {
        uint256 mintAmount = 1000 ether;
        uint256 approvalAmount = 500 ether;
        uint256 transferAmount = 300 ether;
        uint256 burnAmount = 200 ether;

        // Mint to user1
        vm.prank(vault);
        token.mint(user1, mintAmount);

        // User1 approves user2
        vm.prank(user1);
        token.approve(user2, approvalAmount);

        // User2 transfers from user1 to unauthorized
        vm.prank(user2);
        token.transferFrom(user1, unauthorized, transferAmount);

        // Vault burns from unauthorized
        vm.prank(vault);
        token.burn(unauthorized, burnAmount);

        assertEq(token.balanceOf(user1), mintAmount - transferAmount, "User1 final balance");
        assertEq(token.balanceOf(unauthorized), transferAmount - burnAmount, "Unauthorized final balance");
        assertEq(token.totalSupply(), mintAmount - burnAmount, "Final total supply");
        assertEq(token.allowance(user1, user2), approvalAmount - transferAmount, "Remaining allowance");
    }

    function test_MultipleUsersComplexInteractions() public {
        // Mint to multiple users
        vm.startPrank(vault);
        token.mint(user1, 1000 ether);
        token.mint(user2, 500 ether);
        vm.stopPrank();

        // User1 transfers to unauthorized
        vm.prank(user1);
        token.transfer(unauthorized, 200 ether);

        // User2 approves user1
        vm.prank(user2);
        token.approve(user1, 300 ether);

        // User1 transfers from user2 to unauthorized
        vm.prank(user1);
        token.transferFrom(user2, unauthorized, 100 ether);

        // Vault burns from unauthorized
        vm.prank(vault);
        token.burn(unauthorized, 150 ether);

        assertEq(token.balanceOf(user1), 800 ether, "User1 final balance");
        assertEq(token.balanceOf(user2), 400 ether, "User2 final balance");
        assertEq(token.balanceOf(unauthorized), 150 ether, "Unauthorized final balance");
        assertEq(token.totalSupply(), 1350 ether, "Final total supply");
    }
}
