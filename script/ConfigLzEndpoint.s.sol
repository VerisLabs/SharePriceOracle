// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/MaxLzEndpoint.sol";
import "../src/SharePriceOracle.sol";
import "./libs/ChainConfig.sol";

contract ConfigLzEndpoint is Script {
    error ConfigNotFound(string path);
    error InvalidConfig(string reason);

    struct DeploymentInfo {
        address oracle;
        address endpoint;
        address admin;
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
    }

    function getDeploymentInfo(
        string memory networkName, 
        uint32 chainId
    ) internal view returns (DeploymentInfo memory info) {
        string memory path = string.concat(
            "deployments/",
            networkName,
            "_",
            vm.toString(chainId),
            ".json"
        );

        if (!vm.exists(path)) {
            revert ConfigNotFound(path);
        }

        string memory json = vm.readFile(path);
        
        // Read each field individually to avoid stack issues
        info.oracle = vm.parseJsonAddress(json, ".oracle");
        info.endpoint = vm.parseJsonAddress(json, ".endpoint");
        info.admin = vm.parseJsonAddress(json, ".admin");
        info.chainId = uint32(vm.parseJsonUint(json, ".chainId"));
        info.lzEndpointId = uint32(vm.parseJsonUint(json, ".lzEndpointId"));
        info.lzEndpoint = vm.parseJsonAddress(json, ".lzEndpoint");
        
        return info;
    }

    function run() external {
        // Get current chain config
        ChainConfig.Config memory currentChain = ChainConfig.getConfig(block.chainid);
        
        // Load deployments info
        DeploymentInfo memory srcInfo = getDeploymentInfo(
            currentChain.name,
            currentChain.chainId
        );

        // Load private key
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start configuration
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(srcInfo.endpoint));
        SharePriceOracle oracle = SharePriceOracle(srcInfo.oracle);

        // Configure peers for each supported chain
        uint256[] memory targetChainIds = vm.envUint("TARGET_CHAIN_IDS", ",");
        for (uint256 i = 0; i < targetChainIds.length; i++) {
            // Get target chain config
            ChainConfig.Config memory targetChain = ChainConfig.getConfig(targetChainIds[i]);
            DeploymentInfo memory targetInfo = getDeploymentInfo(
                targetChain.name,
                targetChain.chainId
            );

            // Convert target endpoint address to bytes32 peer ID
            bytes32 targetPeer = bytes32(uint256(uint160(targetInfo.endpoint)));
            
            // Set peer
            endpoint.setPeer(targetChain.chainId, targetPeer);
            console.log(
                string.concat(
                    "Set peer for ", 
                    targetChain.name,
                    " (", 
                    vm.toString(targetChain.chainId),
                    "): ",
                    vm.toString(targetInfo.endpoint)
                )
            );

            // Verify peer setting
            bytes32 setPeer = endpoint.peers(targetChain.chainId);
            if (setPeer != targetPeer) {
                revert InvalidConfig("Peer verification failed");
            }
        }

        // Grant ENDPOINT_ROLE to the endpoint in the oracle if not already granted
        if (!oracle.hasRole(address(endpoint), oracle.ENDPOINT_ROLE())) {
            oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());
            console.log("Granted ENDPOINT_ROLE to:", address(endpoint));
        }

        vm.stopBroadcast();

        console.log("\nConfiguration Summary:");
        console.log("======================");
        console.log("Current Network:", currentChain.name);
        console.log("Chain ID:", currentChain.chainId);
        console.log("Oracle:", srcInfo.oracle);
        console.log("Endpoint:", srcInfo.endpoint);
    }
}
