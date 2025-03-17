// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Chainlink.sol";
import "../../src/adapters/curve/Curve2Pool.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { ICurvePool } from "../../src/interfaces/curve/ICurvePool.sol";
import { ISharePriceRouter } from "../../src/interfaces/ISharePriceRouter.sol";
import { CurveBaseAdapter } from "src/adapters/curve/CurveBaseAdapter.sol";

contract TestCurve2PoolAssetAdapter is Test {
    address private CHAINLINK_PRICE_FEED_ETH = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address private CURVE_PRICE_FEED_CBETH = 0x11C1fBd4b3De66bC0565779b35171a6CF3E71f59;
    address constant SEQUENCER_FEED = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CBETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;

    // Heartbeat values from config
    uint256 constant ETH_HEARTBEAT = 1200; // 20 minutes

    // Test contracts
    address public admin;
    Curve2PoolAssetAdapter public adapter;
    ChainlinkAdapter public chainlinkAdapter;
    SharePriceRouter public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceRouter(address(this));

        adapter = new Curve2PoolAssetAdapter(
            address(this), // admin
            address(router), // oracle
            address(router) // router
        );

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        adapter.setReentrancyConfig(2, 10_000);

        // Deploy adapter
        chainlinkAdapter = new ChainlinkAdapter(
            address(this), // admin
            address(router), // oracle
            address(router) // router
        );
        // Grant ORACLE_ROLE to test contract
        chainlinkAdapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        chainlinkAdapter.addAsset(WETH, CHAINLINK_PRICE_FEED_ETH, 0, true);

        // Configure price feeds in router
        router.setLocalAssetConfig(WETH, address(chainlinkAdapter), CHAINLINK_PRICE_FEED_ETH, 0, true);
        router.setLocalAssetConfig(CBETH, address(adapter), CURVE_PRICE_FEED_CBETH, 0, true);

        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.quoteTokenDecimals = 18;
        data.baseTokenDecimals = 18;
        data.upperBound = 10_200;
        data.lowerBound = 10_000;

        adapter.addAsset(CBETH, data);
    }

    function testReturnsCorrectPrice() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(CBETH, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("CBETH/USD Price", priceData.price);
    }

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();
        adapter.removeAsset(CBETH);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__AssetIsNotSupported.selector);
        adapter.getPrice(CBETH, true);
    }

    function testRevertAddAsset__InvalidPool() public {
        adapter.setReentrancyConfig(2, 6000);

        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 9800;

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidPoolAddress.selector);
        adapter.addAsset(CBETH, data);
    }

    function testRevertAddAsset__InvalidAsset() public {
        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 9800;

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidAsset.selector);
        adapter.addAsset(WETH, data);
    }

    function testRevertAddAsset__InvalidBounds() public {
        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 10_201;

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.addAsset(CBETH, data);

        data.upperBound = 10_400;
        data.lowerBound = 9800;

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.addAsset(CBETH, data);
    }

    function testRevertAddAsset__InvalidAssetIndex() public {
        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 0;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 9800;

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidAssetIndex.selector);
        adapter.addAsset(CBETH, data);

        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 1;
        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidAssetIndex.selector);
        adapter.addAsset(CBETH, data);
    }

    function testUpdateAsset() public {
        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 9800;

        adapter.addAsset(CBETH, data);
        adapter.addAsset(CBETH, data);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__AssetIsNotSupported.selector);
        adapter.removeAsset(WETH);
    }

    function testRaiseBounds() public {
        Curve2PoolAssetAdapter.AdapterData memory data;
        data.pool = CURVE_PRICE_FEED_CBETH;
        data.baseToken = WETH;
        data.quoteTokenIndex = 1;
        data.baseTokenIndex = 0;
        data.upperBound = 10_200;
        data.lowerBound = 10_000;
        adapter.addAsset(CBETH, data);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_000, 10_000);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_000, 10_600);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_000, 10_100);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_100, 10_200);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_300, 10_400);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__InvalidBounds.selector);
        adapter.raiseBounds(CBETH, 10_100, 10_500);

        vm.expectRevert(Curve2PoolAssetAdapter.Curve2PoolAssetAdapter__BoundsExceeded.selector);
        adapter.raiseBounds(CBETH, 10_200, 10_400);

        adapter.raiseBounds(CBETH, 10_050, 10_300);
    }

    function testIsLocked() public {
        vm.expectRevert(CurveBaseAdapter.CurveBaseAdapter__PoolNotFound.selector);
        adapter.isLocked(CBETH, 0);

        adapter.setReentrancyConfig(3, 10_000);
        assertEq(adapter.isLocked(CBETH, 3), true);

        adapter.setReentrancyConfig(4, 10_000);
        assertEq(adapter.isLocked(CBETH, 4), true);
    }

    function testSetReentrancyConfig() public {
        vm.expectRevert(CurveBaseAdapter.CurveBaseAdapter__InvalidConfiguration.selector);
        adapter.setReentrancyConfig(4, 100);

        vm.expectRevert(CurveBaseAdapter.CurveBaseAdapter__InvalidConfiguration.selector);
        adapter.setReentrancyConfig(5, 10_000);

        vm.expectRevert(CurveBaseAdapter.CurveBaseAdapter__InvalidConfiguration.selector);
        adapter.setReentrancyConfig(1, 10_000);
    }
}
