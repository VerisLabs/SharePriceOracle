// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/MaxLzEndpoint.sol";
import "./libs/ChainConfig.sol";

contract ConfigLzEndpoint is Script {
    error ConfigNotFound(string path);
    error UnsupportedEndpointId(uint32 lzEndpointId);

    struct DeploymentInfo {
        address router;
        address endpoint;
        address chainlinkAdapter;
        address api3Adapter;
        address admin;
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
    }

    function getDeploymentInfo(
        string memory networkName,
        uint32 chainId
    )
        internal
        view
        returns (DeploymentInfo memory info)
    {
        string memory path = string.concat("deployments/", networkName, "_", vm.toString(chainId), ".json");

        if (!vm.exists(path)) {
            revert ConfigNotFound(path);
        }

        string memory json = vm.readFile(path);

        info.router = vm.parseJsonAddress(json, ".router");
        info.endpoint = vm.parseJsonAddress(json, ".endpoint");
        info.chainlinkAdapter = vm.parseJsonAddress(json, ".chainlinkAdapter");
        info.api3Adapter = vm.parseJsonAddress(json, ".api3Adapter");
        info.admin = vm.parseJsonAddress(json, ".admin");
        info.chainId = uint32(vm.parseJsonUint(json, ".chainId"));
        info.lzEndpointId = uint32(vm.parseJsonUint(json, ".lzEndpointId"));
        info.lzEndpoint = vm.parseJsonAddress(json, ".lzEndpoint");

        return info;
    }

    // Get chain name for a given LZ endpoint ID
    function getChainNameForLzId(uint32 lzEndpointId) internal pure returns (string memory, bool) {
        if (lzEndpointId == 30110) {
            return ("Arbitrum", true);
        } else if (lzEndpointId == 30111) {
            return ("Optimism", true);
        } else if (lzEndpointId == 30109) {
            return ("Polygon", true);
        } else if (lzEndpointId == 30184) {
            return ("Base", true);
        } else if (lzEndpointId == 31337) {
            return ("Anvil", true);
        }
        return ("", false);
    }

    // Get chain ID for a given LZ endpoint ID
    function getChainIdForLzId(uint32 lzEndpointId) internal pure returns (uint32, bool) {
        if (lzEndpointId == 30110) {
            return (42161, true); // Arbitrum
        } else if (lzEndpointId == 30111) {
            return (10, true); // Optimism
        } else if (lzEndpointId == 30109) {
            return (137, true); // Polygon
        } else if (lzEndpointId == 30184) {
            return (8453, true); // Base
        } else if (lzEndpointId == 31337) {
            return (31337, true); // Anvil
        }
        return (0, false);
    }

    function run() external {
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console.log("Configuring LayerZero for chain:", config.name);

        // Get the current chain's deployment info
        string memory deploymentPath =
            string.concat("deployments/", config.name, "_", vm.toString(config.chainId), ".json");
        
        if (!vm.exists(deploymentPath)) {
            console.log("Deployment file not found:", deploymentPath);
            console.log("Please deploy to this chain first using the deploy command");
            return;
        }
        
        string memory json = vm.readFile(deploymentPath);
        address endpointAddress = vm.parseJsonAddress(json, ".endpoint");
        console.log("Local endpoint address:", vm.toString(endpointAddress));

        // Start broadcast
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get the MaxLzEndpoint contract
        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(endpointAddress));
        
        // Get target endpoint IDs from environment
        uint256[] memory targetEndpointIds = vm.envUint("TARGET_ENDPOINT_IDS", ",");
        console.log("Configuring peers for endpoint IDs:", vm.toString(targetEndpointIds.length));
        
        for (uint256 i = 0; i < targetEndpointIds.length; i++) {
            uint32 targetLzId = uint32(targetEndpointIds[i]);
            console.log("Processing endpoint ID:", vm.toString(targetLzId));
            
            (string memory targetChainName, bool nameSuccess) = getChainNameForLzId(targetLzId);
            (uint32 targetChainId, bool idSuccess) = getChainIdForLzId(targetLzId);
            
            if (!nameSuccess || !idSuccess) {
                console.log("Unknown endpoint ID:", vm.toString(targetLzId));
                console.log("Skipping peer configuration for this endpoint ID");
                continue;
            }
            
            console.log("Target chain:", targetChainName);
            
            // Get the target chain's deployment info
            string memory targetPath =
                string.concat("deployments/", targetChainName, "_", vm.toString(targetChainId), ".json");
            
            if (!vm.exists(targetPath)) {
                console.log("Target deployment file not found:", targetPath);
                console.log("Skipping peer configuration for", targetChainName);
                continue;
            }
            
            string memory targetJson = vm.readFile(targetPath);
            address targetEndpoint = vm.parseJsonAddress(targetJson, ".endpoint");
            console.log("Target endpoint address:", vm.toString(targetEndpoint));
            
            bytes32 targetPeer = bytes32(uint256(uint160(targetEndpoint)));
            
            try endpoint.setPeer(targetLzId, targetPeer) {
                console.log(
                    string.concat(
                        "Set peer for ",
                        targetChainName,
                        " (lzId: ",
                        vm.toString(targetLzId),
                        ") to: ",
                        vm.toString(targetEndpoint)
                    )
                );
            } catch Error(string memory reason) {
                console.log(
                    string.concat(
                        "Failed to set peer for ",
                        targetChainName,
                        ": ",
                        reason
                    )
                );
            } catch {
                console.log(
                    string.concat(
                        "Failed to set peer for ",
                        targetChainName,
                        " with unknown error"
                    )
                );
            }
        }

        vm.stopBroadcast();
    }
} 