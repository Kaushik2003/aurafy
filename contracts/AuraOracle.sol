// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title AuraOracle
 * @notice Stores and manages aura scores for creator vaults with IPFS evidence
 * @dev Oracle-controlled updates with cooldown enforcement and audit trail
 */
contract AuraOracle is Ownable {
    // State variables
    address public oracleAddress;
    uint256 public constant ORACLE_UPDATE_COOLDOWN = 6 hours;

    // Storage mappings
    mapping(address => uint256) private vaultAura;
    mapping(address => string) private vaultIpfsHash;
    mapping(address => uint256) private lastUpdateTimestamp;

    // Events
    event AuraUpdated(address indexed vault, uint256 aura, string ipfsHash, uint256 timestamp);
    event OracleAddressUpdated(address indexed oldOracle, address indexed newOracle);

    // Custom errors
    error Unauthorized();
    error CooldownNotElapsed();

    /**
     * @notice Constructor sets initial owner and oracle address
     * @param initialOwner Address that will own the contract
     * @param _oracleAddress Address authorized to push aura updates
     */
    constructor(address initialOwner, address _oracleAddress) Ownable(initialOwner) {
        oracleAddress = _oracleAddress;
    }

    /**
     * @notice Modifier to restrict function access to oracle address only
     */
    modifier onlyOracle() {
        if (msg.sender != oracleAddress) {
            revert Unauthorized();
        }
        _;
    }

    /**
     * @notice Push new aura value for a vault with IPFS evidence
     * @dev Enforces cooldown period and oracle-only access
     * @param vault Address of the creator vault
     * @param aura New aura score (0-200 range)
     * @param ipfsHash IPFS hash containing metrics evidence
     */
    function pushAura(address vault, uint256 aura, string calldata ipfsHash) external onlyOracle {
        // Check cooldown (skip for first update)
        if (lastUpdateTimestamp[vault] != 0) {
            if (block.timestamp < lastUpdateTimestamp[vault] + ORACLE_UPDATE_COOLDOWN) {
                revert CooldownNotElapsed();
            }
        }

        // Update storage
        vaultAura[vault] = aura;
        vaultIpfsHash[vault] = ipfsHash;
        lastUpdateTimestamp[vault] = block.timestamp;

        // Emit event
        emit AuraUpdated(vault, aura, ipfsHash, block.timestamp);
    }

    /**
     * @notice Get current aura value for a vault
     * @param vault Address of the creator vault
     * @return Current aura score
     */
    function getAura(address vault) external view returns (uint256) {
        return vaultAura[vault];
    }

    /**
     * @notice Get IPFS hash for a vault's last aura update
     * @param vault Address of the creator vault
     * @return IPFS hash string
     */
    function getIpfsHash(address vault) external view returns (string memory) {
        return vaultIpfsHash[vault];
    }

    /**
     * @notice Get last update timestamp for a vault
     * @param vault Address of the creator vault
     * @return Timestamp of last aura update
     */
    function getLastUpdateTimestamp(address vault) external view returns (uint256) {
        return lastUpdateTimestamp[vault];
    }

    /**
     * @notice Update the oracle address
     * @dev Only owner can update. Used for oracle key rotation.
     * @param newOracle New oracle address
     */
    function setOracleAddress(address newOracle) external onlyOwner {
        address oldOracle = oracleAddress;
        oracleAddress = newOracle;
        emit OracleAddressUpdated(oldOracle, newOracle);
    }
}
