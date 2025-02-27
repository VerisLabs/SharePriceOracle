// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { stdJson } from "forge-std/StdJson.sol";
import { ChainConfig } from "./libs/ChainConfig.sol";
import { ChainlinkAdapter } from "../src/adapters/Chainlink.sol";
import { Api3Adapter } from "../src/adapters/Api3.sol";
import { SharePriceRouter } from "../src/SharePriceRouter.sol";

/**
 * @title ConfigPriceFeeds
 * @notice Script to configure price feeds for the SharePriceOracle system
 */
contract ConfigPriceFeeds is Script {
    using stdJson for string;

    // Deployment information structure
    struct DeploymentInfo {
        address router;
        address chainlinkAdapter;
        address api3Adapter;
    }

    // Token configuration structure
    struct TokenConfig {
        address tokenAddress;
        address chainlinkFeed;
        uint256 heartbeat;
        string symbol;
    }

    function run() external {
        // Get basic chain information
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        string memory chainName = config.name;
        string memory lowerChainName = _toLower(chainName);
        console.log("Chain:", chainName, "ID:", config.chainId);

        // Load deployment information
        string memory deploymentPath =
            string.concat("deployments/", chainName, "_", vm.toString(config.chainId), ".json");
        DeploymentInfo memory deployment = _readDeploymentInfo(deploymentPath);

        // Get contract instances
        ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(deployment.chainlinkAdapter);
        SharePriceRouter router = SharePriceRouter(deployment.router);

        // Load configuration and tokens
        string memory priceFeedConfigJson = vm.readFile("script/config/priceFeedConfig.json");
        string memory chainTokensPath = string.concat(".chain_tokens.", lowerChainName, ".tokens");
        string[] memory tokenKeys = vm.parseJsonKeys(priceFeedConfigJson, chainTokensPath);
        console.log("Found", tokenKeys.length, "tokens for", chainName);

        // Get private keys
        uint256 backendKey = vm.envUint("BACKEND_PRIVATE_KEY");
        uint256 adminKey = vm.envUint("PRIVATE_KEY");

        // Phase 1: Add assets to adapters using backend key
        _configureAdapters(chainlinkAdapter, tokenKeys, priceFeedConfigJson, chainTokensPath, backendKey);

        // Phase 2: Set asset categories in router using admin key
        _configureAssetCategories(router, tokenKeys, priceFeedConfigJson, chainTokensPath, adminKey);
    }

    // Read deployment information from JSON file
    function _readDeploymentInfo(string memory path) internal view returns (DeploymentInfo memory) {
        string memory json = vm.readFile(path);

        DeploymentInfo memory info;
        info.router = json.readAddress(".router");
        info.chainlinkAdapter = json.readAddress(".chainlinkAdapter");
        info.api3Adapter = json.readAddress(".api3Adapter");

        return info;
    }

    // Configure adapters with asset information
    function _configureAdapters(
        ChainlinkAdapter chainlinkAdapter,
        string[] memory tokenKeys,
        string memory configJson,
        string memory chainTokensPath,
        uint256 privateKey
    )
        internal
    {
        vm.startBroadcast(privateKey);
        console.log("Phase 1: Adding assets to adapters");

        for (uint256 i = 0; i < tokenKeys.length; i++) {
            string memory symbol = tokenKeys[i];
            address tokenAddress = _getTokenAddress(configJson, chainTokensPath, symbol);
            if (tokenAddress == address(0)) continue;

            // Process Chainlink feed
            (address feed, uint256 heartbeat) = _getChainlinkFeedInfo(configJson, symbol);
            if (feed != address(0)) {
                _addAssetToChainlink(chainlinkAdapter, tokenAddress, feed, heartbeat, symbol);
            }
        }

        vm.stopBroadcast();
    }

    // Configure asset categories in the router
    function _configureAssetCategories(
        SharePriceRouter router,
        string[] memory tokenKeys,
        string memory configJson,
        string memory chainTokensPath,
        uint256 privateKey
    )
        internal
    {
        vm.startBroadcast(privateKey);
        console.log("Phase 2: Setting asset categories in router");

        for (uint256 i = 0; i < tokenKeys.length; i++) {
            string memory symbol = tokenKeys[i];
            address tokenAddress = _getTokenAddress(configJson, chainTokensPath, symbol);
            if (tokenAddress == address(0)) continue;

            SharePriceRouter.AssetCategory category = _getAssetCategory(symbol);
            if (category == SharePriceRouter.AssetCategory.UNKNOWN) {
                console.log("Skipping unknown category for", symbol);
                continue;
            }

            try router.setAssetCategory(tokenAddress, category) {
                console.log("Set category for", symbol, ":", uint8(category));
            } catch Error(string memory reason) {
                console.log("Failed to set category for", symbol, ":", reason);
            } catch {
                console.log("Failed to set category for", symbol);
            }
        }

        vm.stopBroadcast();
    }

    // Get token address from configuration
    function _getTokenAddress(
        string memory configJson,
        string memory basePath,
        string memory symbol
    )
        internal
        view
        returns (address)
    {
        string memory tokenPath = string.concat(basePath, ".", symbol);
        try vm.parseJsonAddress(configJson, tokenPath) returns (address addr) {
            return addr;
        } catch {
            console.log("Failed to parse address for", symbol);
            return address(0);
        }
    }

    // Get Chainlink feed information
    function _getChainlinkFeedInfo(
        string memory configJson,
        string memory symbol
    )
        internal
        view
        returns (address feed, uint256 heartbeat)
    {
        string memory basePath = string.concat(".base_price_feeds.", symbol);

        try vm.parseJsonAddress(configJson, string.concat(basePath, ".feed")) returns (address addr) {
            feed = addr;
        } catch {
            return (address(0), 0);
        }

        try vm.parseJsonUint(configJson, string.concat(basePath, ".heartbeat")) returns (uint256 value) {
            heartbeat = value;
        } catch {
            // Default heartbeat
            heartbeat = 86_400; // 24 hours
        }

        return (feed, heartbeat);
    }

    // Add asset to Chainlink adapter
    function _addAssetToChainlink(
        ChainlinkAdapter adapter,
        address token,
        address feed,
        uint256 heartbeat,
        string memory symbol
    )
        internal
    {
        console.log("Adding", symbol, "to Chainlink. Feed:", feed);

        try adapter.addAsset(token, feed, heartbeat, true) {
            console.log("Successfully added to Chainlink");
        } catch Error(string memory reason) {
            console.log("Failed to add to Chainlink:", reason);
        } catch {
            console.log("Failed to add to Chainlink");
        }
    }

    // Helper function to determine asset category based on token symbol
    function _getAssetCategory(string memory symbol) internal pure returns (SharePriceRouter.AssetCategory) {
        bytes32 symbolHash = keccak256(bytes(symbol));

        // BTC-like assets
        if (_isBtcLike(symbolHash)) {
            return SharePriceRouter.AssetCategory.BTC_LIKE;
        }

        // ETH-like assets
        if (_isEthLike(symbolHash)) {
            return SharePriceRouter.AssetCategory.ETH_LIKE;
        }

        // Stablecoins
        if (_isStable(symbolHash)) {
            return SharePriceRouter.AssetCategory.STABLE;
        }

        return SharePriceRouter.AssetCategory.UNKNOWN;
    }

    // Check if symbol is BTC-like
    function _isBtcLike(bytes32 symbolHash) internal pure returns (bool) {
        return (
            symbolHash == keccak256(bytes("WBTC")) || symbolHash == keccak256(bytes("BTCB"))
                || symbolHash == keccak256(bytes("tBTC")) || symbolHash == keccak256(bytes("cbBTC"))
        );
    }

    // Check if symbol is ETH-like
    function _isEthLike(bytes32 symbolHash) internal pure returns (bool) {
        return (
            symbolHash == keccak256(bytes("WETH")) || symbolHash == keccak256(bytes("ETH"))
                || symbolHash == keccak256(bytes("stETH")) || symbolHash == keccak256(bytes("wstETH"))
                || symbolHash == keccak256(bytes("rETH")) || symbolHash == keccak256(bytes("rsETH"))
                || symbolHash == keccak256(bytes("weETH")) || symbolHash == keccak256(bytes("cbETH"))
                || symbolHash == keccak256(bytes("frxETH")) || symbolHash == keccak256(bytes("OETH"))
                || symbolHash == keccak256(bytes("ezETH"))
        );
    }

    // Check if symbol is a stablecoin
    function _isStable(bytes32 symbolHash) internal pure returns (bool) {
        return (
            symbolHash == keccak256(bytes("USDC")) || symbolHash == keccak256(bytes("USDCe"))
                || symbolHash == keccak256(bytes("USDT")) || symbolHash == keccak256(bytes("USDe"))
                || symbolHash == keccak256(bytes("USDz")) || symbolHash == keccak256(bytes("DAI"))
                || symbolHash == keccak256(bytes("sUSDe"))
        );
    }

    // Convert string to lowercase
    function _toLower(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bLower = new bytes(bStr.length);

        for (uint256 i = 0; i < bStr.length; i++) {
            if (uint8(bStr[i]) >= 65 && uint8(bStr[i]) <= 90) {
                bLower[i] = bytes1(uint8(bStr[i]) + 32);
            } else {
                bLower[i] = bStr[i];
            }
        }

        return string(bLower);
    }
}
