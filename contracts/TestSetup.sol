// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/// @title TestSetup
/// @notice Temporary contract to verify OpenZeppelin dependencies are correctly installed
contract TestSetup is ERC20, Ownable, ReentrancyGuard, Pausable {
    constructor() ERC20("Test", "TST") Ownable(msg.sender) {}
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
