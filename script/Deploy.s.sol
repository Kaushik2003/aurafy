// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "../contracts/Treasury.sol";
import "../contracts/AuraOracle.sol";
import "../contracts/VaultFactory.sol";

/**
 * @title Deploy
 * @notice Deployment script for AuraFi protocol on Celo Alfajores testnet
 * @dev Deploys Treasury, AuraOracle, and VaultFactory with default configurations
 */
contract Deploy is Script {
    // Deployed contract instances
    Treasury public treasury;
    AuraOracle public oracle;
    VaultFactory public factory;

    function run() public {
        address deployer = msg.sender;
        
        console.log("=== AuraFi Deployment Script ===");
        console.log("Deployer address:", deployer);
        console.log("");

        vm.startBroadcast();

        // 1. Deploy Treasury
        console.log("Deploying Treasury...");
        treasury = new Treasury(deployer);
        console.log("Treasury deployed at:", address(treasury));
        console.log("");

        // 2. Deploy AuraOracle with deployer as initial oracle address
        console.log("Deploying AuraOracle...");
        oracle = new AuraOracle(deployer, deployer);
        console.log("AuraOracle deployed at:", address(oracle));
        console.log("Oracle address set to:", deployer);
        console.log("");

        // 3. Deploy VaultFactory
        console.log("Deploying VaultFactory...");
        factory = new VaultFactory(
            deployer,
            address(treasury),
            address(oracle)
        );
        console.log("VaultFactory deployed at:", address(factory));
        console.log("");

        vm.stopBroadcast();

        // Log deployment summary
        console.log("=== Deployment Summary ===");
        console.log("Treasury:", address(treasury));
        console.log("AuraOracle:", address(oracle));
        console.log("VaultFactory:", address(factory));
        console.log("");
        console.log("Default stage configurations initialized:");
        console.log("  Stage 0: 0 CELO stake, 0 tokens capacity");
        console.log("  Stage 1: 100 CELO stake, 500 tokens capacity");
        console.log("  Stage 2: 300 CELO stake, 2500 tokens capacity");
        console.log("  Stage 3: 800 CELO stake, 9500 tokens capacity");
        console.log("  Stage 4: 1800 CELO stake, 34500 tokens capacity");
        console.log("");

        // Save deployment addresses to JSON file
        _saveDeploymentAddresses();
    }

    /**
     * @notice Save deployment addresses to deployments.json file
     * @dev Uses vm.writeJson to create a JSON file with all deployed contract addresses
     */
    function _saveDeploymentAddresses() internal {
        string memory json = "deploymentData";
        
        vm.serializeAddress(json, "treasury", address(treasury));
        vm.serializeAddress(json, "oracle", address(oracle));
        string memory finalJson = vm.serializeAddress(json, "factory", address(factory));
        
        vm.writeJson(finalJson, "./deployments.json");
        console.log("Deployment addresses saved to deployments.json");
    }
}
