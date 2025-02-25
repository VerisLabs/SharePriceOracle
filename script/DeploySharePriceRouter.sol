// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/SharePriceRouter.sol";
import "../src/MaxLzEndpoint.sol";
import "../src/adapters/Chainlink.sol";
import "../src/adapters/Api3.sol";
import "./libs/ChainConfig.sol";

contract DeploySharePriceRouter is Script {
    // Struct to help reduce stack depth
    struct DeploymentData {
        address router;
        address endpoint;
        address chainlinkAdapter;
        address api3Adapter;
        address admin;
    }

    // Helper function to create JSON for deployment data
    function createDeploymentJson(
        ChainConfig.Config memory config,
        DeploymentData memory data
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "{",
                _jsonPair("router", vm.toString(data.router), true),
                _jsonPair("endpoint", vm.toString(data.endpoint), true),
                _jsonPair("chainlinkAdapter", vm.toString(data.chainlinkAdapter), true),
                _jsonPair("api3Adapter", vm.toString(data.api3Adapter), true),
                _jsonPair("admin", vm.toString(data.admin), true),
                _jsonPairNum("chainId", vm.toString(config.chainId), true),
                _jsonPairNum("lzEndpointId", vm.toString(config.lzEndpointId), true),
                _jsonPair("lzEndpoint", vm.toString(config.lzEndpoint), true),
                _jsonPair("network", config.name, false),
                "}"
            )
        );
    }

    // Helper function to create JSON key-value pair - moved to internal function with underscore prefix
    function _jsonPair(string memory key, string memory value, bool addComma) internal pure returns (string memory) {
        if (addComma) {
            return string.concat('"', key, '": "', value, '",');
        } else {
            return string.concat('"', key, '": "', value, '"');
        }
    }

    // Helper function to create JSON key-value pair for numbers - moved to internal function with underscore prefix
    function _jsonPairNum(string memory key, string memory value, bool addComma) internal pure returns (string memory) {
        if (addComma) {
            return string.concat('"', key, '": ', value, ',');
        } else {
            return string.concat('"', key, '": ', value);
        }
    }

    // Helper function to get token addresses for the current chain
    function getTokenAddresses(uint256 chainId) internal pure returns (address usdc, address wbtc, address weth) {
        if (chainId == 8453) { // Base
            usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
            wbtc = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
            weth = 0x4200000000000000000000000000000000000006;
        } else if (chainId == 42161) { // Arbitrum
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            wbtc = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
            weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
        } else if (chainId == 10) { // Optimism
            usdc = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
            wbtc = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
            weth = 0x4200000000000000000000000000000000000006;
        } else if (chainId == 137) { // Polygon
            usdc = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
            wbtc = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
            weth = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
        } else {
            // Default to Ethereum mainnet addresses if chain not explicitly supported
            usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
            wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
            weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
    }

    // Helper function to log deployment details
    function logDeployment(
        string memory networkName,
        uint256 chainId,
        DeploymentData memory data
    ) internal view {
        console.log("Deployment Summary:");
        console.log("==================");
        console.log("Network:", networkName);
        console.log("Chain ID:", chainId);
        console.log("SharePriceRouter:", data.router);
        console.log("MaxLzEndpoint:", data.endpoint);
        console.log("ChainlinkAdapter:", data.chainlinkAdapter);
        console.log("Api3Adapter:", data.api3Adapter);
        console.log("Admin:", data.admin);
    }

    // Save deployment data to file - simplified to reduce stack depth
    function saveDeployment(
        ChainConfig.Config memory config,
        DeploymentData memory data
    ) internal {
        string memory deploymentPath = string.concat(
            "deployments/", 
            config.name, 
            "_", 
            vm.toString(config.chainId), 
            ".json"
        );
        
        string memory jsonContent = createDeploymentJson(config, data);
        vm.writeFile(deploymentPath, jsonContent);
        console.log("Deployment saved to:", deploymentPath);
    }

    function run() external {
        // Load private key from env
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));
        address oracle = vm.envOr("ORACLE_ADDRESS", address(0));
        if (admin == address(0)) {
            admin = vm.addr(deployerPrivateKey);
        }

        // Start broadcast
        vm.startBroadcast(deployerPrivateKey);

        // Load configuration
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);

        // Get token addresses for the current chain
        (address usdc, address wbtc, address weth) = getTokenAddresses(block.chainid);

        // Create deployment data struct to track addresses
        DeploymentData memory deploymentData;
        deploymentData.admin = admin;

        // Deploy contracts
        SharePriceRouter router = new SharePriceRouter(
            admin,
            config.ethUsdFeed,
            usdc,
            wbtc,
            weth
        );
        deploymentData.router = address(router);

        ChainlinkAdapter chainlinkAdapter = new ChainlinkAdapter(
            admin,
            oracle,
            address(router)
        );
        deploymentData.chainlinkAdapter = address(chainlinkAdapter);

        Api3Adapter api3Adapter = new Api3Adapter(
            admin,
            oracle,
            address(router),
            weth
        );
        deploymentData.api3Adapter = address(api3Adapter);

        MaxLzEndpoint endpoint = new MaxLzEndpoint(
            admin,
            config.lzEndpoint,
            address(router)
        );
        deploymentData.endpoint = address(endpoint);

        // Setup permissions if flag is set
        if (vm.envOr("SETUP_PERMISSIONS", false)) {
            router.grantRole(address(endpoint), router.ENDPOINT_ROLE());
            router.addAdapter(address(chainlinkAdapter), 1);
            router.addAdapter(address(api3Adapter), 2);
        }

        vm.stopBroadcast();

        // Log deployment details
        logDeployment(
            config.name,
            config.chainId,
            deploymentData
        );

        // Save deployment details
        saveDeployment(config, deploymentData);
    }
}