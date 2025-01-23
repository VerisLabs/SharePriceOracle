// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/SharePriceOracle.sol";
import "./libs/ChainConfig.sol";
import {PriceDenomination} from "../src/interfaces/ISharePriceOracle.sol";

contract SetPriceFeedsScript is Script {
    struct FeedData {
        uint32 chainId;
        address token;
        address feed;
        PriceDenomination denomination;
    }

    uint256 constant BATCH_SIZE = 10;
    string internal configJson;
    SharePriceOracle internal oracle;

    function getFeedDataForChain(
        string memory chain,
        uint32 chainId
    ) internal view returns (FeedData[] memory chainFeeds, uint256 feedCount) {
        string memory tokensPath = string.concat(".chain_tokens.", chain, ".tokens");
        string[] memory tokens = vm.parseJsonKeys(configJson, tokensPath);
        
        chainFeeds = new FeedData[](tokens.length);
        feedCount = 0;

        for (uint256 j = 0; j < tokens.length; j++) {
            string memory tokenPath = string.concat(tokensPath, ".", tokens[j]);
            address tokenAddress = vm.parseJsonAddress(configJson, tokenPath);

            string memory feedPath = string.concat(".base_price_feeds.", tokens[j]);
            address feed = vm.parseJsonAddress(configJson, string.concat(feedPath, ".feed"));
            string memory denom = vm.parseJsonString(configJson, string.concat(feedPath, ".denomination"));

            chainFeeds[feedCount] = FeedData({
                chainId: chainId,
                token: tokenAddress,
                feed: feed,
                denomination: keccak256(bytes(denom)) == keccak256(bytes("ETH")) ? 
                    PriceDenomination.ETH : 
                    PriceDenomination.USD
            });
            feedCount++;
        }
    }

    function processBatch(FeedData[] memory feeds, uint256 start, uint256 end) internal {
        for (uint256 j = start; j < end; j++) {
            FeedData memory data = feeds[j];
            oracle.setPriceFeed(
                data.chainId,
                data.token,
                PriceFeedInfo({
                    feed: data.feed,
                    denomination: data.denomination
                })
            );
            
            console.log(
                string.concat(
                    "Set feed for chain ", 
                    vm.toString(data.chainId),
                    " token: ",
                    vm.toString(data.token)
                )
            );
        }
    }

    function run() external {
        require(block.chainid == 8453, "Must be run on Base");
        
        // Get deployment info
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        string memory deploymentPath = string.concat(
            "deployments/",
            config.name,
            "_",
            vm.toString(config.chainId),
            ".json"
        );
        string memory deployJson = vm.readFile(deploymentPath);
        address oracleAddress = vm.parseJsonAddress(deployJson, ".oracle");
        
        // Load price feed config
        configJson = vm.readFile("script/config/priceFeedConfig.json");
        oracle = SharePriceOracle(oracleAddress);
        
        // Get all chains
        string[] memory chains = vm.parseJsonKeys(configJson, ".chain_tokens");
        
        // Process each chain
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        for (uint256 i = 0; i < chains.length; i++) {
            string memory chainPath = string.concat(".chain_tokens.", chains[i]);
            uint32 chainId = uint32(vm.parseJsonUint(configJson, string.concat(chainPath, ".chainId")));
            
            // Get feeds for this chain
            (FeedData[] memory chainFeeds, uint256 feedCount) = getFeedDataForChain(chains[i], chainId);
            
            // Process in batches
            uint256 batches = (feedCount + BATCH_SIZE - 1) / BATCH_SIZE;
            
            for (uint256 batchIdx = 0; batchIdx < batches; batchIdx++) {
                uint256 start = batchIdx * BATCH_SIZE;
                uint256 end = start + BATCH_SIZE > feedCount ? feedCount : start + BATCH_SIZE;
                
                console.log(
                    string.concat(
                        "\nProcessing batch ", 
                        vm.toString(batchIdx + 1), 
                        "/",
                        vm.toString(batches),
                        " for chain ",
                        chains[i]
                    )
                );

                processBatch(chainFeeds, start, end);
                
                // If not the last batch, stop broadcast and start a new one
                if (batchIdx < batches - 1) {
                    vm.stopBroadcast();
                    vm.startBroadcast(deployerPrivateKey);
                }
            }
        }

        vm.stopBroadcast();
    }
}
