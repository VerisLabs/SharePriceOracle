// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import "../src/SharePriceRouter.sol";
import "./libs/ChainConfig.sol";

contract ConfigCrossChainAssets is Script {
    error ConfigNotFound(string path);

    struct DeploymentInfo {
        address router;
        uint32 chainId;
    }

    struct CrossChainMapping {
        string srcChain;
        string srcAsset;
        string dstAsset;
    }

    function run() external {
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        DeploymentInfo memory deployment = getDeploymentInfo(config.name, config.chainId);
        
        // Load price feed configuration
        string memory priceFeedJson = vm.readFile("script/config/priceFeedConfig.json");
        
        // Admin setup
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(adminPrivateKey);
        
        // Initialize router
        SharePriceRouter router = SharePriceRouter(deployment.router);
        
        // Only configure Base chain (8453)
        if (config.chainId != 8453) {
            console.log("Cross-chain asset mapping is only configured for Base chain (8453)");
            vm.stopBroadcast();
            return;
        }
        
        // Define correct mappings (direct equivalents, not exchange rates)
        // For each source chain asset, map to its same-type equivalent on Base
        
        // Arbitrum mappings - map to same asset type on Base
        setupMapping("arbitrum", "USDT", "USDT", router, config, priceFeedJson); // Not USDC
        setupMapping("arbitrum", "WETH", "WETH", router, config, priceFeedJson);
        setupMapping("arbitrum", "WBTC", "WBTC", router, config, priceFeedJson);
        
        // Optimism mappings - map to same asset type on Base
        setupMapping("optimism", "USDCe", "USDC", router, config, priceFeedJson); // This is correct as USDCe is the USDC equivalent
        setupMapping("optimism", "WETH", "WETH", router, config, priceFeedJson);
        setupMapping("optimism", "WBTC", "WBTC", router, config, priceFeedJson);
        
        // Polygon mappings - map to same asset type on Base
        setupMapping("polygon", "USDC", "USDC", router, config, priceFeedJson);
        setupMapping("polygon", "WETH", "WETH", router, config, priceFeedJson);
        setupMapping("polygon", "WBTC", "WBTC", router, config, priceFeedJson);
        
        vm.stopBroadcast();
    }
    
    function setupMapping(
        string memory srcChain,
        string memory srcAsset,
        string memory dstAsset,
        SharePriceRouter router,
        ChainConfig.Config memory config,
        string memory priceFeedJson
    ) internal {
        // Get chain ID for source chain
        uint32 srcChainId = getChainId(srcChain);
        if (srcChainId == 0) {
            console.log("Unknown source chain:", srcChain);
            return;
        }
        
        // Get token addresses for source and destination assets
        address srcTokenAddress = getTokenAddress(priceFeedJson, srcChain, srcAsset);
        address dstTokenAddress = getTokenAddress(priceFeedJson, config.name, dstAsset);
        
        if (srcTokenAddress == address(0)) {
            console.log("Could not find address for source token:", srcChain, srcAsset);
            return;
        }
        
        if (dstTokenAddress == address(0)) {
            console.log("Could not find address for destination token:", config.name, dstAsset);
            return;
        }
        
        // Set the cross-chain asset mapping
        try router.setCrossChainAssetMapping(srcChainId, srcTokenAddress, dstTokenAddress) {
        } catch Error(string memory reason) {
            console.log("Failed to set mapping:", reason);
        } catch {
            console.log("Failed to set mapping for:", srcChain);
            console.log("srcAsset:", srcAsset);
            console.log("to:", config.name); 
            console.log("asset:", dstAsset);
        }
    }
    
    // Helper functions
    function getDeploymentInfo(string memory networkName, uint32 chainId) internal view returns (DeploymentInfo memory) {
        string memory path = string.concat("deployments/", networkName, "_", vm.toString(chainId), ".json");
        if (!vm.exists(path)) revert ConfigNotFound(path);
        
        string memory json = vm.readFile(path);
        DeploymentInfo memory info;
        info.router = vm.parseJsonAddress(json, ".router");
        info.chainId = chainId;
        return info;
    }
    
    function getTokenAddress(string memory json, string memory chain, string memory asset) internal view returns (address) {
        string memory path = string.concat(".chain_tokens.", toLowercase(chain), ".tokens.", asset);
        try vm.parseJsonAddress(json, path) returns (address addr) {
            return addr;
        } catch {
            return address(0);
        }
    }
    
    function getChainId(string memory chain) internal pure returns (uint32) {
        if (equalStrings(chain, "arbitrum")) return 42161;
        if (equalStrings(chain, "optimism")) return 10;
        if (equalStrings(chain, "polygon")) return 137;
        return 0;
    }
    
    function toLowercase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);
        
        for (uint i = 0; i < bStr.length; i++) {
            if ((uint8(bStr[i]) >= 65) && (uint8(bStr[i]) <= 90)) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }
        
        return string(bLower);
    }
    
    function equalStrings(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
} 
