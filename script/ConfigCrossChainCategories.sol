// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SharePriceRouter.sol";
import "./libs/ChainConfig.sol";

contract ConfigCrossChainCategories is Script {
    error ConfigNotFound(string path);

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

    struct CrossChainAsset {
        string chain;
        string symbol;
        address tokenAddress;
        SharePriceRouter.AssetCategory category;
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

    function getAssetCategory(string memory symbol) internal pure returns (SharePriceRouter.AssetCategory) {
        bytes32 symbolHash = keccak256(bytes(symbol));
        
        // BTC-like assets
        if (
            symbolHash == keccak256(bytes("WBTC")) ||
            symbolHash == keccak256(bytes("BTC")) ||
            symbolHash == keccak256(bytes("BTCB"))
        ) {
            return SharePriceRouter.AssetCategory.BTC_LIKE;
        }
        
        // ETH-like assets
        if (
            symbolHash == keccak256(bytes("WETH")) ||
            symbolHash == keccak256(bytes("ETH"))
        ) {
            return SharePriceRouter.AssetCategory.ETH_LIKE;
        }
        
        // Stablecoins
        if (
            symbolHash == keccak256(bytes("USDC")) ||
            symbolHash == keccak256(bytes("USDT")) ||
            symbolHash == keccak256(bytes("DAI")) ||
            symbolHash == keccak256(bytes("BUSD")) ||
            symbolHash == keccak256(bytes("TUSD")) ||
            symbolHash == keccak256(bytes("USDP")) ||
            symbolHash == keccak256(bytes("USDD"))
        ) {
            return SharePriceRouter.AssetCategory.STABLE;
        }
        
        // Default to UNKNOWN for any other asset
        return SharePriceRouter.AssetCategory.UNKNOWN;
    }

    function run() external {
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        DeploymentInfo memory deployment = getDeploymentInfo(config.name, config.chainId);

        // Load price feed configuration
        string memory priceFeedConfigPath = "script/config/priceFeedConfig.json";
        string memory priceFeedJson = vm.readFile(priceFeedConfigPath);

        // Debug logging
        console.log("Chain name:", config.name);
        console.log("Chain ID:", config.chainId);

        // Use PRIVATE_KEY for admin operations (setting asset categories requires ADMIN_ROLE)
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address adminAddress = vm.addr(adminPrivateKey);
        console.log("Admin address:", adminAddress);

        // Start broadcast with the admin private key
        vm.startBroadcast(adminPrivateKey);

        // Get router
        SharePriceRouter router = SharePriceRouter(deployment.router);

        // Define cross-chain assets to set categories for
        CrossChainAsset[] memory assets = new CrossChainAsset[](6);
        uint256 assetCount = 0;
        
        // Arbitrum assets
        assets[assetCount++] = CrossChainAsset({
            chain: "arbitrum",
            symbol: "USDT",
            tokenAddress: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9,
            category: SharePriceRouter.AssetCategory.STABLE
        });
        
        assets[assetCount++] = CrossChainAsset({
            chain: "arbitrum",
            symbol: "WETH",
            tokenAddress: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1,
            category: SharePriceRouter.AssetCategory.ETH_LIKE
        });
        
        assets[assetCount++] = CrossChainAsset({
            chain: "arbitrum",
            symbol: "WBTC",
            tokenAddress: 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f,
            category: SharePriceRouter.AssetCategory.BTC_LIKE
        });
        
        // Optimism assets
        assets[assetCount++] = CrossChainAsset({
            chain: "optimism",
            symbol: "USDC",
            tokenAddress: 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85,
            category: SharePriceRouter.AssetCategory.STABLE
        });
        
        assets[assetCount++] = CrossChainAsset({
            chain: "optimism",
            symbol: "WETH",
            tokenAddress: 0x4200000000000000000000000000000000000006,
            category: SharePriceRouter.AssetCategory.ETH_LIKE
        });
        
        assets[assetCount++] = CrossChainAsset({
            chain: "optimism",
            symbol: "WBTC",
            tokenAddress: 0x68f180fcCe6836688e9084f035309E29Bf0A2095,
            category: SharePriceRouter.AssetCategory.BTC_LIKE
        });
        
        // Process each asset
        for (uint256 i = 0; i < assetCount; i++) {
            CrossChainAsset memory asset = assets[i];
            console.log("Setting category for", asset.chain, asset.symbol);
            
            // Get the local asset address from the cross-chain mapping
            bytes32 key = keccak256(abi.encodePacked(
                keccak256(bytes(asset.chain)) == keccak256(bytes("arbitrum")) ? uint32(42161) : 
                keccak256(bytes(asset.chain)) == keccak256(bytes("optimism")) ? uint32(10) : 
                uint32(0),
                asset.tokenAddress
            ));
            
            address localAsset = router.crossChainAssetMap(key);
            
            if (localAsset == address(0)) {
                console.log("No cross-chain mapping found for", asset.chain, asset.symbol);
                continue;
            }
            
            console.log("Local asset address:", localAsset);
            
            // Set the asset category for the cross-chain asset
            try router.setAssetCategory(
                asset.tokenAddress,
                asset.category
            ) {
                console.log("Successfully set asset category for", asset.chain, asset.symbol);
            } catch Error(string memory reason) {
                console.log("Failed to set asset category:", reason);
            } catch {
                console.log("Failed to set asset category with unknown error");
            }
        }

        vm.stopBroadcast();
    }
} 