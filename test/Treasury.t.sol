// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {Treasury} from "../contracts/Treasury.sol";

contract TreasuryTest is Test {
    Treasury public treasury;

    address public owner = address(1);
    address public vault = address(2);
    address public recipient = address(3);
    address public nonOwner = address(4);

    // Events (must be declared in test contract for vm.expectEmit)
    event TreasuryCollected(address indexed vault, uint256 amount, string reason);
    event Withdrawn(address indexed to, uint256 amount);

    function setUp() public {
        vm.prank(owner);
        treasury = new Treasury(owner);
    }

    // ============ Fee Collection Tests ============

    function test_CollectFee() public {
        uint256 feeAmount = 1 ether;

        vm.deal(vault, feeAmount);
        vm.prank(vault);

        treasury.collectFee{value: feeAmount}();

        assertEq(treasury.getBalance(), feeAmount, "Treasury balance should equal fee amount");
    }

    function test_CollectFee_EmitsEvent() public {
        uint256 feeAmount = 0.5 ether;

        vm.deal(vault, feeAmount);
        vm.prank(vault);

        vm.expectEmit(true, false, false, true);
        emit TreasuryCollected(vault, feeAmount, "Mint fee");

        treasury.collectFee{value: feeAmount}();
    }

    function test_CollectFee_MultipleTimes() public {
        uint256 fee1 = 1 ether;
        uint256 fee2 = 0.5 ether;
        uint256 fee3 = 2 ether;

        // First collection
        vm.deal(vault, fee1);
        vm.prank(vault);
        treasury.collectFee{value: fee1}();

        // Second collection
        vm.deal(vault, fee2);
        vm.prank(vault);
        treasury.collectFee{value: fee2}();

        // Third collection
        vm.deal(vault, fee3);
        vm.prank(vault);
        treasury.collectFee{value: fee3}();

        assertEq(treasury.getBalance(), fee1 + fee2 + fee3, "Treasury should accumulate all fees");
    }

    function test_CollectFee_ZeroAmount() public {
        vm.prank(vault);
        treasury.collectFee{value: 0}();

        assertEq(treasury.getBalance(), 0, "Treasury balance should be 0");
    }

    // ============ Withdrawal Tests ============

    function test_Withdraw_ByOwner() public {
        // Fund treasury
        uint256 fundAmount = 10 ether;
        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        // Withdraw
        uint256 withdrawAmount = 5 ether;
        uint256 recipientBalanceBefore = recipient.balance;

        vm.prank(owner);
        treasury.withdraw(recipient, withdrawAmount);

        assertEq(treasury.getBalance(), fundAmount - withdrawAmount, "Treasury balance should decrease");
        assertEq(recipient.balance, recipientBalanceBefore + withdrawAmount, "Recipient should receive funds");
    }

    function test_Withdraw_FullBalance() public {
        // Fund treasury
        uint256 fundAmount = 10 ether;
        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        // Withdraw full balance
        vm.prank(owner);
        treasury.withdraw(recipient, fundAmount);

        assertEq(treasury.getBalance(), 0, "Treasury balance should be 0");
        assertEq(recipient.balance, fundAmount, "Recipient should receive full amount");
    }

    function test_Withdraw_EmitsEvent() public {
        // Fund treasury
        uint256 fundAmount = 10 ether;
        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        // Withdraw with event check
        uint256 withdrawAmount = 3 ether;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit Withdrawn(recipient, withdrawAmount);

        treasury.withdraw(recipient, withdrawAmount);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        // Fund treasury
        uint256 fundAmount = 10 ether;
        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        // Try to withdraw as non-owner
        vm.prank(nonOwner);
        vm.expectRevert();
        treasury.withdraw(recipient, 1 ether);
    }

    function test_RevertWhen_WithdrawExceedsBalance() public {
        // Fund treasury with small amount
        uint256 fundAmount = 1 ether;
        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        // Try to withdraw more than balance
        vm.prank(owner);
        vm.expectRevert(Treasury.InsufficientBalance.selector);
        treasury.withdraw(recipient, 2 ether);
    }

    function test_RevertWhen_WithdrawFromEmptyTreasury() public {
        // Try to withdraw from empty treasury
        vm.prank(owner);
        vm.expectRevert(Treasury.InsufficientBalance.selector);
        treasury.withdraw(recipient, 1 ether);
    }

    // ============ Receive Function Tests ============

    function test_ReceiveDirectTransfer() public {
        uint256 amount = 5 ether;

        vm.deal(vault, amount);
        vm.prank(vault);
        (bool success,) = address(treasury).call{value: amount}("");

        assertTrue(success, "Direct transfer should succeed");
        assertEq(treasury.getBalance(), amount, "Treasury should receive direct transfer");
    }

    function test_ReceiveDirectTransfer_EmitsEvent() public {
        uint256 amount = 2 ether;

        vm.deal(vault, amount);
        vm.prank(vault);

        vm.expectEmit(true, false, false, true);
        emit TreasuryCollected(vault, amount, "Direct transfer");

        (bool success,) = address(treasury).call{value: amount}("");
        assertTrue(success, "Direct transfer should succeed");
    }

    // ============ Balance Query Tests ============

    function test_GetBalance_Empty() public view {
        assertEq(treasury.getBalance(), 0, "Initial balance should be 0");
    }

    function test_GetBalance_AfterCollection() public {
        uint256 amount = 7 ether;

        vm.deal(vault, amount);
        vm.prank(vault);
        treasury.collectFee{value: amount}();

        assertEq(treasury.getBalance(), amount, "Balance should reflect collected fees");
    }

    function test_GetBalance_AfterWithdrawal() public {
        // Fund and withdraw
        uint256 fundAmount = 10 ether;
        uint256 withdrawAmount = 3 ether;

        vm.deal(vault, fundAmount);
        vm.prank(vault);
        treasury.collectFee{value: fundAmount}();

        vm.prank(owner);
        treasury.withdraw(recipient, withdrawAmount);

        assertEq(treasury.getBalance(), fundAmount - withdrawAmount, "Balance should reflect withdrawal");
    }

    // ============ Integration Tests ============

    function test_MultipleVaultsCollectFees() public {
        address vault1 = address(10);
        address vault2 = address(11);
        address vault3 = address(12);

        uint256 fee1 = 1 ether;
        uint256 fee2 = 2 ether;
        uint256 fee3 = 0.5 ether;

        // Vault 1 collects
        vm.deal(vault1, fee1);
        vm.prank(vault1);
        treasury.collectFee{value: fee1}();

        // Vault 2 collects
        vm.deal(vault2, fee2);
        vm.prank(vault2);
        treasury.collectFee{value: fee2}();

        // Vault 3 collects
        vm.deal(vault3, fee3);
        vm.prank(vault3);
        treasury.collectFee{value: fee3}();

        assertEq(treasury.getBalance(), fee1 + fee2 + fee3, "Treasury should accumulate fees from all vaults");
    }

    function test_CollectWithdrawCollectCycle() public {
        // Collect fees
        uint256 fee1 = 5 ether;
        vm.deal(vault, fee1);
        vm.prank(vault);
        treasury.collectFee{value: fee1}();

        assertEq(treasury.getBalance(), fee1, "Balance after first collection");

        // Withdraw partial
        uint256 withdraw1 = 2 ether;
        vm.prank(owner);
        treasury.withdraw(recipient, withdraw1);

        assertEq(treasury.getBalance(), fee1 - withdraw1, "Balance after withdrawal");

        // Collect more fees
        uint256 fee2 = 3 ether;
        vm.deal(vault, fee2);
        vm.prank(vault);
        treasury.collectFee{value: fee2}();

        assertEq(treasury.getBalance(), fee1 - withdraw1 + fee2, "Balance after second collection");

        // Withdraw remaining
        uint256 finalBalance = treasury.getBalance();
        vm.prank(owner);
        treasury.withdraw(recipient, finalBalance);

        assertEq(treasury.getBalance(), 0, "Balance should be 0 after final withdrawal");
    }
}
