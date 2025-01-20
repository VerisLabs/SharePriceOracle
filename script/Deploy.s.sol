// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/SharePriceOracle.sol";
import "../src/MaxLzEndpoint.sol";
import "./libs/ChainConfig.sol";

contract DeployScript is Script {
    function saveDeployment(
        ChainConfig.Config memory config,
        address oracle,
        address endpoint,
        address admin
    ) internal {
        string memory deploymentPath = string.concat(
            "deployments/", 
            config.name,
            "_",
            vm.toString(config.chainId),
            ".json"
        );

        // Create JSON object incrementally to avoid stack too deep
        vm.writeJson(vm.toString(oracle), deploymentPath, ".oracle");
        vm.writeJson(vm.toString(endpoint), deploymentPath, ".endpoint");
        vm.writeJson(vm.toString(admin), deploymentPath, ".admin");
        vm.writeJson(vm.toString(config.chainId), deploymentPath, ".chainId");
        vm.writeJson(vm.toString(config.lzEndpointId), deploymentPath, ".lzEndpointId");
        vm.writeJson(vm.toString(config.lzEndpoint), deploymentPath, ".lzEndpoint");
        vm.writeJson(config.name, deploymentPath, ".network");
    }

    function run() external {
        // Load configuration
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        
        // Load private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        if (admin == address(0)) {
            admin = vm.addr(deployerPrivateKey);
        }

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Deploy SharePriceOracle
        SharePriceOracle oracle = new SharePriceOracle(
            config.chainId,
            admin,
            config.ethUsdFeed
        );

        // Deploy MaxLzEndpoint
        MaxLzEndpoint endpoint = new MaxLzEndpoint(
            admin,
            config.lzEndpoint,
            address(oracle)
        );

        // Setup permissions if flag is set
        bool setupPermissions = vm.envOr("SETUP_PERMISSIONS", false);
        if (setupPermissions) {
            oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());
        }

        vm.stopBroadcast();

        // Log deployment
        console.log("Deployment Summary:");
        console.log("==================");
        console.log("Network:", config.name);
        console.log("Chain ID:", config.chainId);
        console.log("SharePriceOracle:", address(oracle));
        console.log("MaxLzEndpoint:", address(endpoint));
        console.log("Admin:", admin);

        // Save deployment details
        saveDeployment(config, address(oracle), address(endpoint), admin);
    }
}
