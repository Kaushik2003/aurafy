// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title CreatorToken
 * @notice ERC20 token representing fan ownership in a creator's vault
 * @dev Mint and burn operations are restricted to the associated CreatorVault contract only
 */
contract CreatorToken is ERC20 {
    // State variables
    address public immutable vault;

    // Custom errors
    error Unauthorized();

    // Modifiers
    /**
     * @notice Restricts function access to the vault contract only
     */
    modifier onlyVault() {
        if (msg.sender != vault) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Constructor sets token name, symbol, and vault address
     * @param name Token name (e.g., "Creator Token")
     * @param symbol Token symbol (e.g., "CRTR")
     * @param _vault Address of the CreatorVault contract that can mint/burn
     */
    constructor(string memory name, string memory symbol, address _vault) ERC20(name, symbol) {
        vault = _vault;
    }

    /**
     * @notice Mint tokens to a specified address
     * @dev Only callable by the vault contract
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyVault {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from a specified address
     * @dev Only callable by the vault contract
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     */
    function burn(address from, uint256 amount) external onlyVault {
        _burn(from, amount);
    }
}
