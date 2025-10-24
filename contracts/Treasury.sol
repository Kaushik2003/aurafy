// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Treasury
 * @notice Collects protocol fees from CreatorVault minting operations
 * @dev Owner-controlled withdrawal with event tracking for fee collection
 */
contract Treasury is Ownable {
    // Events
    event TreasuryCollected(address indexed vault, uint256 amount, string reason);
    event Withdrawn(address indexed to, uint256 amount);

    // Custom errors
    error InsufficientBalance();
    error TransferFailed();

    constructor(address initialOwner) Ownable(initialOwner) {}

    /**
     * @notice Receive fees from vaults
     * @dev Payable function that accepts CELO and emits collection event
     */
    function collectFee() external payable {
        emit TreasuryCollected(msg.sender, msg.value, "Mint fee");
    }

    /**
     * @notice Withdraw funds from treasury
     * @dev Only owner can withdraw. Transfers specified amount to recipient.
     * @param to Address to receive the withdrawn funds
     * @param amount Amount of CELO to withdraw (in wei)
     */
    function withdraw(address to, uint256 amount) external onlyOwner {
        if (address(this).balance < amount) {
            revert InsufficientBalance();
        }

        (bool success,) = to.call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit Withdrawn(to, amount);
    }

    /**
     * @notice Get current treasury balance
     * @return Current CELO balance in wei
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Fallback function to receive CELO
     */
    receive() external payable {
        emit TreasuryCollected(msg.sender, msg.value, "Direct transfer");
    }
}
