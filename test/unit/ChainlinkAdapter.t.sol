// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { ChainlinkAdapter } from "../../src/adapters/Chainlink.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { ISharePriceRouter, PriceReturnData } from "../../src/interfaces/ISharePriceRouter.sol";
import { SharePriceRouter } from "../../src/SharePriceRouter.sol";

contract ChainlinkAdapterTest is Test {
    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    
    // Chainlink price feed addresses on BASE (from priceFeedConfig.json)
    address constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
    address constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;
    
    // Heartbeat values from config
    uint256 constant ETH_HEARTBEAT = 1200;  // 20 minutes
    uint256 constant BTC_HEARTBEAT = 1200;  // 20 minutes
    
    // Test contracts
    ChainlinkAdapter public adapter;
    SharePriceRouter public router;
    
    function setUp() public {
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router
        router = new SharePriceRouter(
            address(this),  // admin
            ETH_USD_FEED,  // ETH/USD feed
            USDC,
            WBTC,
            WETH
        );

        // Set sequencer feed
        router.setSequencer(SEQUENCER_FEED);

        // Deploy adapter
        adapter = new ChainlinkAdapter(
            address(this),  // admin
            address(router),  // oracle
            address(router)  // router
        );

        // Add adapter to router
        router.addAdapter(address(adapter), 1);

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Add assets
        adapter.addAsset(
            WETH,
            ETH_USD_FEED,
            ETH_HEARTBEAT,
            true  // USD feed
        );

        adapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            BTC_HEARTBEAT,
            true  // USD feed
        );
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        assertEq(priceData.inUSD, true, "Price should be in USD");

        // Log the actual price for verification
        emit log_named_uint("ETH/USD Price", priceData.price);
    }

    function testReturnsCorrectPrice_WBTC_USD() public {
        PriceReturnData memory priceData = adapter.getPrice(WBTC, true);
        
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        assertEq(priceData.inUSD, true, "Price should be in USD");

        // Log the actual price for verification
        emit log_named_uint("BTC/USD Price", priceData.price);
    }

    function testPriceError_StaleTimestamp() public {
        // Mock sequencer to be down (answer = 1 means sequencer is down)
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92233720368547777, // roundId
                int256(1),  // 1 = sequencer is down
                block.timestamp,  // startedAt 
                block.timestamp,  // updatedAt
                92233720368547777  // answeredInRound
            )
        );

        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__SequencerDown.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_SequencerGracePeriod() public {
        // Mock sequencer just came back up but still in grace period
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92233720368547777, // roundId
                int256(0),  // 0 = sequencer is up
                block.timestamp - 30 minutes,  // startedAt (within grace period)
                block.timestamp,  // updatedAt
                92233720368547777  // answeredInRound
            )
        );

        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__SequencerDown.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_StalePrice() public {
        // Mock sequencer to be up and past grace period
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92233720368547777, // roundId
                int256(0),  // 0 = sequencer is up
                block.timestamp - 2 hours,  // startedAt (past grace period)
                block.timestamp,  // updatedAt
                92233720368547777  // answeredInRound
            )
        );

        // Mock price feed with stale timestamp
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92233720368547777, // roundId
                int256(2000e8),  // 2000 USD
                block.timestamp - 5 hours,  // startedAt
                block.timestamp - 5 hours,  // updatedAt
                92233720368547777  // answeredInRound
            )
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, true, "Should error on stale price");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
    }

    function testRevertAfterAssetRemove() public {
        // Get price before removal to ensure it works
        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error before removal");
        assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

        // Remove the asset
        adapter.removeAsset(WETH);

        // Verify it reverts after removal
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.getPrice(WETH, true);
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__InvalidHeartbeat.selector);
        adapter.addAsset(
            WETH,
            ETH_USD_FEED,
            25 hours, // More than DEFAULT_HEART_BEAT
            true
        );
    }

    function testCanAddSameAsset() public {
        // Should be able to add the same asset again
        adapter.addAsset(
            WETH,
            ETH_USD_FEED,
            1 hours,
            true
        );

        // Verify it still works
        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("ETH/USD Price after re-add", priceData.price);
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.removeAsset(address(0));
    }
} 