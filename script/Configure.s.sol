// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { AddressBook } from "../src/libs/AddressBook.sol";
import { SharePriceRouter } from "../src/SharePriceRouter.sol";
import { ChainlinkAdapter } from "../src/adapters/Chainlink.sol";
import { MaxLzEndpoint } from "../src/MaxLzEndpoint.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract Configure is Script {
    using stdJson for string;

    function run() external {
        // Only run on Base chain
        require(block.chainid == AddressBook.BASE, "This script is only for Base chain");

        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        address chainlinkAdapterAddress = vm.envAddress("CHAINLINK_ADAPTER_ADDRESS");
        address maxLzEndpointAddress = vm.envAddress("BASE_MAX_LZ_ENDPOINT_ADDRESS");
        
        SharePriceRouter router = SharePriceRouter(routerAddress);
        ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(chainlinkAdapterAddress);
        MaxLzEndpoint maxLzEndpoint = MaxLzEndpoint(payable(maxLzEndpointAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Configure Chainlink price feeds
        _configureChainlinkFeeds(chainlinkAdapter);

        // Configure cross-chain asset mappings
        _configureCrossChainMappings(router);

        // Configure LZ endpoints
        _configureLzEndpoints(maxLzEndpoint);

        vm.stopBroadcast();
    }

    function _configureChainlinkFeeds(ChainlinkAdapter adapter) internal {
        AddressBook.AssetConfig[] memory baseAssets = AddressBook.getBaseAssets();
        
        for (uint256 i = 0; i < baseAssets.length; i++) {
            adapter.addAsset(
                baseAssets[i].token,
                baseAssets[i].priceFeed,
                baseAssets[i].heartbeat,
                baseAssets[i].inUSD
            );
            console2.log(
                "Configured price feed for token:",
                baseAssets[i].token,
                "category:",
                uint256(baseAssets[i].category)
            );
        }
    }

    function _configureCrossChainMappings(SharePriceRouter router) internal {
        // Get Base assets for mapping
        AddressBook.AssetConfig[] memory baseAssets = AddressBook.getBaseAssets();

        // Configure Optimism mappings
        address[] memory optimismAssets = AddressBook.getOptimismAssets();
        for (uint256 i = 0; i < optimismAssets.length - 1; i++) {
            router.setCrossChainAssetMapping(
                AddressBook.OPTIMISM,
                optimismAssets[i],
                baseAssets[i].token
            );
            console2.log(
                "Mapped Optimism asset:",
                optimismAssets[i],
                "to Base asset:",
                baseAssets[i].token
            );
        }
        
        // Manual mapping for Optimism USDCe to Base USDC
        router.setCrossChainAssetMapping(
            AddressBook.OPTIMISM,
            optimismAssets[6], // USDCe
            baseAssets[0].token // Base USDC
        );
        console2.log("Mapped Optimism USDCe:", optimismAssets[6]);
        console2.log("to Base USDC:", baseAssets[0].token);

        // Configure Arbitrum mappings
        address[] memory arbitrumAssets = AddressBook.getArbitrumAssets();
        for (uint256 i = 0; i < arbitrumAssets.length; i++) {
            router.setCrossChainAssetMapping(
                AddressBook.ARBITRUM,
                arbitrumAssets[i],
                baseAssets[i].token
            );
            console2.log(
                "Mapped Arbitrum asset:",
                arbitrumAssets[i],
                "to Base asset:",
                baseAssets[i].token
            );
        }
    }

    function _configureLzEndpoints(MaxLzEndpoint maxLzEndpoint) internal {
        // Get remote chain configs from ChainConfig library
        (uint32 optimismLzId, address optimismLzEndpoint,) = AddressBook.getChainConfig(AddressBook.OPTIMISM);
        (uint32 arbitrumLzId, address arbitrumLzEndpoint,) = AddressBook.getChainConfig(AddressBook.ARBITRUM);

        // Read MaxLzEndpoint addresses from deployment files
        address optimismMaxLz = vm.envAddress("OP_MAX_LZ_ENDPOINT_ADDRESS");
        address arbitrumMaxLz = vm.envAddress("ARB_MAX_LZ_ENDPOINT_ADDRESS");

        // Set peers for each chain on Base
        maxLzEndpoint.setPeer(optimismLzId, bytes32(uint256(uint160(optimismMaxLz))));
        console2.log("Setting peer for Optimism");
        console2.log("LZ ID:", optimismLzId);
        console2.log("MaxLzEndpoint:", optimismMaxLz);
        console2.log("LZ Endpoint:", optimismLzEndpoint);

        maxLzEndpoint.setPeer(arbitrumLzId, bytes32(uint256(uint160(arbitrumMaxLz))));
        console2.log("Setting peer for Arbitrum");
        console2.log("LZ ID:", arbitrumLzId);
        console2.log("MaxLzEndpoint:", arbitrumMaxLz);
        console2.log("LZ Endpoint:", arbitrumLzEndpoint);
    }
} 