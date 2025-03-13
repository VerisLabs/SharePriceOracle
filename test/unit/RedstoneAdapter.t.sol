// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/RedStone.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { IRedstone } from "../../src/interfaces/redstone/IRedstone.sol";
import { ISharePriceRouter } from "../../src/interfaces/ISharePriceRouter.sol";

contract RedstoneAdapterTest is Test {
    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address constant BSDETH = 0xCb327b99fF831bF8223cCEd12B1338FF3aA322Ff;

    // RedStone price feed addresses on BASE (from priceFeedConfig.json)
    address constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
    address constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;
    address constant BSDETH_ETH_FEED = 0xC49F0Dd98F38C525A7ce15E73E60675456F3a161;

    // Heartbeat values from config
    uint256 constant BSDETH_HEARTBEAT = 86400; // 1 day
    uint256 constant BTC_HEARTBEAT = 86400; // 1 day

    address public admin;
    RedStoneAdapter public adapter;
    SharePriceRouter public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        router = new SharePriceRouter(address(this));
        router.setSequencer(SEQUENCER_FEED);

        adapter = new RedStoneAdapter(
            address(this), 
            address(router), 
            address(router) 
        );

        router.setLocalAssetConfig(BSDETH, address(adapter), BSDETH_ETH_FEED, 0, true);
        router.setLocalAssetConfig(WETH, address(adapter), ETH_USD_FEED, 0, true);
        router.setLocalAssetConfig(WBTC, address(adapter), BTC_USD_FEED, 0, true);

        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(0), 
                block.timestamp - 2 hours, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(2000e8), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(42_000e8), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        vm.mockCall(
            BSDETH_ETH_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(1e18), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        vm.mockCall(ETH_USD_FEED, abi.encodeWithSelector(IRedstone.aggregator.selector), abi.encode(ETH_USD_FEED));
        vm.mockCall(BTC_USD_FEED, abi.encodeWithSelector(IRedstone.aggregator.selector), abi.encode(BTC_USD_FEED));
        vm.mockCall(BSDETH_ETH_FEED, abi.encodeWithSelector(IRedstone.aggregator.selector), abi.encode(BSDETH_ETH_FEED));

        vm.mockCall(ETH_USD_FEED, abi.encodeWithSelector(IRedstone.decimals.selector), abi.encode(8));
        vm.mockCall(BTC_USD_FEED, abi.encodeWithSelector(IRedstone.decimals.selector), abi.encode(8));
        vm.mockCall(BSDETH_ETH_FEED, abi.encodeWithSelector(IRedstone.decimals.selector), abi.encode(18));

        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IRedstone.minAnswer.selector),
            abi.encode(int192(1e8)) 
        );
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IRedstone.maxAnswer.selector),
            abi.encode(int192(1e12))
        );
        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IRedstone.minAnswer.selector),
            abi.encode(int192(1e8))
        );
        vm.mockCall(
            BTC_USD_FEED,
            abi.encodeWithSelector(IRedstone.maxAnswer.selector),
            abi.encode(int192(5e12))
        );
        vm.mockCall(
            BSDETH_ETH_FEED,
            abi.encodeWithSelector(IRedstone.minAnswer.selector),
            abi.encode(int192(1e16)) 
        );
        vm.mockCall(
            BSDETH_ETH_FEED,
            abi.encodeWithSelector(IRedstone.maxAnswer.selector),
            abi.encode(int192(5e18)) 
        );

        adapter.addAsset(
            BSDETH,
            BSDETH_ETH_FEED,
            BSDETH_HEARTBEAT,
            false 
        );

        adapter.addAsset(
            WETH,
            ETH_USD_FEED,
            BSDETH_HEARTBEAT,
            true 
        );

        adapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            BTC_HEARTBEAT,
            true 
        );
    }

    function testReturnsCorrectPrice_BSDETH_ETH() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(BSDETH, false);

        assertFalse(priceData.hadError, "Price should not have error");
        assertFalse(priceData.inUSD, "Price should be in ETH");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        emit log_named_uint("BSDETH/ETH Price", priceData.price);
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertEq(priceData.price, 2000e18, "Price should match mocked value");

        emit log_named_uint("ETH/USD Price", priceData.price);
    }

    function testReturnsCorrectPrice_WBTC_USD() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WBTC, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertEq(priceData.price, 42000e18, "Price should match mocked value");
        
        emit log_named_uint("BTC/USD Price", priceData.price);
    }

    function testPriceError_SequencerDown() public {
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(1), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__SequencerDown.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_SequencerGracePeriod() public {
        vm.mockCall(
            SEQUENCER_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, // roundId
                int256(0), // 0 = sequencer is up
                block.timestamp - 30 minutes, // startedAt (within grace period)
                block.timestamp, // updatedAt
                92_233_720_368_547_777 // answeredInRound
            )
        );

        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__SequencerDown.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_BelowMinimum() public {
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(0.5e8), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertTrue(priceData.hadError, "Should error on price below minimum");
    }

    function testPriceError_AboveMaximum() public {
        vm.mockCall(
            ETH_USD_FEED,
            abi.encodeWithSelector(IRedstone.latestRoundData.selector),
            abi.encode(
                92_233_720_368_547_777, 
                int256(12000e8), 
                block.timestamp, 
                block.timestamp, 
                92_233_720_368_547_777 
            )
        );

        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertTrue(priceData.hadError, "Should error on price above maximum");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
    }

    function testRevertAfterAssetRemove() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error before removal");
        assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

        adapter.removeAsset(WETH);

        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__AssetNotSupported.selector);
        adapter.getPrice(WETH, true);
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__InvalidHeartbeat.selector);
        adapter.addAsset(
            makeAddr("newToken"),
            ETH_USD_FEED,
            25 hours, 
            true
        );
    }

    function testRevertAddAsset_InvalidMinMaxConfig() public {
        address testToken = makeAddr("testToken");
        address mockFeed = makeAddr("mockFeed");
        
        vm.mockCall(mockFeed, abi.encodeWithSelector(IRedstone.aggregator.selector), abi.encode(mockFeed));
        vm.mockCall(mockFeed, abi.encodeWithSelector(IRedstone.decimals.selector), abi.encode(8));
        vm.mockCall(
            mockFeed,
            abi.encodeWithSelector(IRedstone.minAnswer.selector),
            abi.encode(int192(100e8)) 
        );
        vm.mockCall(
            mockFeed,
            abi.encodeWithSelector(IRedstone.maxAnswer.selector),
            abi.encode(int192(90e8)) 
        );

        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__InvalidMinMaxConfig.selector);
        adapter.addAsset(
            testToken,
            mockFeed,
            1 hours,
            true
        );
    }

    function testCanAddSameAsset() public {
        adapter.addAsset(WETH, ETH_USD_FEED, 1 hours, true);

        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertFalse(priceData.hadError, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        emit log_named_uint("ETH/USD Price after re-add", priceData.price);
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.expectRevert(RedStoneAdapter.RedStoneAdaptor__AssetNotSupported.selector);
        adapter.removeAsset(address(0));
    }
}