// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Chainlink.sol";
import "../../src/SharePriceOracle.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";

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
    uint256 constant ETH_HEARTBEAT = 1200; // 20 minutes
    uint256 constant BTC_HEARTBEAT = 1200; // 20 minutes

    // Test contracts
    address public admin;
    ChainlinkAdapter public adapter;
    SharePriceOracle public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceOracle(address(this));

        // Set sequencer
        router.setSequencer(SEQUENCER_FEED);

        // Deploy adapter
        adapter = new ChainlinkAdapter(
            address(this), // admin
            address(router), // oracle
            address(router) // router
        );

        // Configure price feeds in router
        router.setLocalAssetConfig(WETH, address(adapter), ETH_USD_FEED, 0, true);
        router.setLocalAssetConfig(WBTC, address(adapter), BTC_USD_FEED, 0, true);

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Mock sequencer to be up and past grace period
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(0), // 0 = sequencer is up
                block.timestamp - 2 hours, // startedAt (past grace period)
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        // Mock ETH/USD price feed
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(2000e8), // 2000 USD
                block.timestamp, // startedAt
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        // Mock BTC/USD price feed
        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(42_000e8), // 42000 USD
                block.timestamp, // startedAt
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        // Mock aggregator functions for both feeds
        vm.mockCall(ETH_USD_FEED, abi.encodeWithSelector(IChainlink.aggregator.selector), abi.encode(ETH_USD_FEED));
        vm.mockCall(BTC_USD_FEED, abi.encodeWithSelector(IChainlink.aggregator.selector), abi.encode(BTC_USD_FEED));

        // Mock decimals for both feeds
        vm.mockCall(ETH_USD_FEED, abi.encodeWithSelector(IChainlink.decimals.selector), abi.encode(8));
        vm.mockCall(BTC_USD_FEED, abi.encodeWithSelector(IChainlink.decimals.selector), abi.encode(8));

        // Mock min/max answers for both feeds
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.minAnswer.selector),
            abi.encode(int192(1e8)) // $1
        );
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.maxAnswer.selector),
            abi.encode(int192(1e12)) // $10000
        );
        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IChainlink.minAnswer.selector),
            abi.encode(int192(1e8)) // $1
        );
        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IChainlink.maxAnswer.selector),
            abi.encode(int192(5e12)) // $50000
        );

        // Add assets to adapter
        adapter.addAsset(
            WETH,
            ETH_USD_FEED,
            ETH_HEARTBEAT,
            true // USD feed
        );

        adapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            BTC_HEARTBEAT,
            true // USD feed
        );
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("ETH/USD Price", priceData.price);
    }

    function testReturnsCorrectPrice_WBTC_USD() public view {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WBTC, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");
    }

    function testPriceError_StaleTimestamp() public {
        // Mock sequencer to be down (answer = 1 means sequencer is down)
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(1), // 1 = sequencer is down
                block.timestamp, // startedAt
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
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
                92_233_720_368_547_777, // roundId
                int256(0), // 0 = sequencer is up
                block.timestamp - 30 minutes, // startedAt (within grace period)
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__SequencerDown.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_StalePriceFeed() public {
        // Mock price feed with stale timestamp
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(2000e8), // 2000 USD
                block.timestamp - 5 hours, // startedAt
                block.timestamp - 5 hours, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertTrue(priceData.hadError, "Should error on stale price");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
    }

    function testRevertAfterAssetRemove() public {
        // First verify we can get a price
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error before removal");
        assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

        // Remove the asset
        adapter.removeAsset(WETH);

        // Verify it reverts after removal
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
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
        adapter.addAsset(WETH, ETH_USD_FEED, 1 hours, true);

        // Verify it still works
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertFalse(priceData.hadError, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("ETH/USD Price after re-add", priceData.price);
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.expectRevert(ChainlinkAdapter.ChainlinkAdaptor__AssetNotSupported.selector);
        adapter.removeAsset(address(0));
    }
}
