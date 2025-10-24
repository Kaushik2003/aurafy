// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./CreatorVault.sol";
import "./CreatorToken.sol";

/**
 * @title VaultFactory
 * @notice Factory contract for deploying CreatorVault and CreatorToken pairs
 * @dev Manages vault creation, stage configuration, and vault registry
 */
contract VaultFactory is Ownable {
    // ============ State Variables ============
    
    /// @notice Address of the Treasury contract for fee collection
    address public immutable treasury;
    
    /// @notice Address of the AuraOracle contract
    address public immutable oracle;
    
    /// @notice Maps creator address to their vault address
    mapping(address => address) public creatorToVault;
    
    // ============ Events ============
    
    event VaultCreated(
        address indexed creator,
        address vault,
        address token,
        uint256 baseCap
    );
    
    event StageConfigured(
        address indexed vault,
        uint8 stage,
        uint256 stakeRequired,
        uint256 mintCap
    );
    
    // ============ Custom Errors ============
    
    error VaultAlreadyExists();
    error InvalidParameters();
    
    // ============ Constructor ============
    
    /**
     * @notice Initialize the VaultFactory
     * @param initialOwner Address that will own the factory contract
     * @param _treasury Address of the Treasury contract
     * @param _oracle Address of the AuraOracle contract
     */
    constructor(
        address initialOwner,
        address _treasury,
        address _oracle
    ) Ownable(initialOwner) {
        if (_treasury == address(0) || _oracle == address(0)) {
            revert InvalidParameters();
        }
        treasury = _treasury;
        oracle = _oracle;
    }
    
    // ============ Functions ============
    
    /**
     * @notice Create a new vault and token for a creator
     * @dev Deploys CreatorToken and CreatorVault, initializes default stage configs
     * @param name Token name (e.g., "Creator Token")
     * @param symbol Token symbol (e.g., "CRTR")
     * @param creator Address of the creator who will own the vault
     * @param baseCap Base capacity for supply cap calculation
     * @return vault Address of the deployed CreatorVault
     * @return token Address of the deployed CreatorToken
     */
    function createVault(
        string calldata name,
        string calldata symbol,
        address creator,
        uint256 baseCap
    ) external returns (address vault, address token) {
        // Validate parameters
        if (creator == address(0) || baseCap == 0) {
            revert InvalidParameters();
        }
        
        // Check if creator already has a vault
        if (creatorToVault[creator] != address(0)) {
            revert VaultAlreadyExists();
        }
        
        // Deploy CreatorVault first with token as address(0) temporarily
        CreatorVault vaultContract = new CreatorVault(
            creator,
            address(0), // Will be set after token deployment
            oracle,
            treasury,
            baseCap,
            address(this) // Factory itself becomes vault owner for admin functions
        );
        
        vault = address(vaultContract);
        
        // Deploy CreatorToken with vault address
        CreatorToken tokenContract = new CreatorToken(
            name,
            symbol,
            vault
        );
        
        token = address(tokenContract);
        
        // Set the token address in the vault
        vaultContract.setToken(token);
        
        // Store vault in registry
        creatorToVault[creator] = vault;
        
        // Initialize default stage configurations
        _initializeDefaultStages(vault);
        
        // Emit event
        emit VaultCreated(creator, vault, token, baseCap);
    }
    
    /**
     * @notice Set stage configuration for a vault
     * @dev Only owner can configure stages. Used to customize stage parameters.
     * @param vault Address of the CreatorVault
     * @param stage Stage number (0-N)
     * @param stakeRequired Cumulative creator stake required to unlock this stage
     * @param mintCap Maximum tokens mintable at this stage (cumulative)
     */
    function setStageConfig(
        address vault,
        uint8 stage,
        uint256 stakeRequired,
        uint256 mintCap
    ) external onlyOwner {
        if (vault == address(0)) {
            revert InvalidParameters();
        }
        
        // Call the vault's setStageConfig function
        CreatorVault(vault).setStageConfig(stage, stakeRequired, mintCap);
        
        // Emit event
        emit StageConfigured(vault, stage, stakeRequired, mintCap);
    }
    
    /**
     * @notice Initialize default stage configurations for a new vault
     * @dev Internal function called during vault creation
     * @param vault Address of the CreatorVault to configure
     */
    function _initializeDefaultStages(address vault) internal {
        // Stage 0: Not bootstrapped (no requirements, no capacity)
        CreatorVault(vault).setStageConfig(0, 0, 0);
        
        // Stage 1: Initial unlock (100 CELO stake, 500 tokens capacity)
        CreatorVault(vault).setStageConfig(1, 100e18, 500e18);
        
        // Stage 2: Growth stage (300 CELO cumulative, 2500 tokens cumulative)
        CreatorVault(vault).setStageConfig(2, 300e18, 2500e18);
        
        // Stage 3: Expansion stage (800 CELO cumulative, 9500 tokens cumulative)
        CreatorVault(vault).setStageConfig(3, 800e18, 9500e18);
        
        // Stage 4: Mature stage (1800 CELO cumulative, 34500 tokens cumulative)
        CreatorVault(vault).setStageConfig(4, 1800e18, 34500e18);
    }
}
