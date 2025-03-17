    // SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { Api3Adapter } from "../../src/adapters/Api3.sol";
import { IProxy } from "../../src/interfaces/api3/IProxy.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";
import { SharePriceOracle } from "../../src/SharePriceOracle.sol";

contract Api3AdapterTest is Test {
    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;

    // API3 price feed addresses on BASE
    address constant DAPI_PROXY_ETH_USD = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address constant DAPI_PROXY_WBTC_USD = 0x041a131Fa91Ad61dD85262A42c04975986580d50;

    // Test contracts
    Api3Adapter public adapter;
    SharePriceOracle public router;

    function setUp() public {
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router
        router = new SharePriceOracle(
            address(this) // admin
        );

        // Deploy adapter
        adapter = new Api3Adapter(
            address(this), // admin
            address(router), // oracle
            address(router), // router
            WETH // WETH address
        );

        // Add adapter to router
        router.setLocalAssetConfig(WETH, address(adapter), DAPI_PROXY_ETH_USD, 0, false);
        router.setLocalAssetConfig(WBTC, address(adapter), DAPI_PROXY_WBTC_USD, 0, false);

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Mock the API3 proxy data for ETH/USD
        vm.mockCall(
            DAPI_PROXY_ETH_USD, abi.encodeWithSelector(IProxy.dapiName.selector), abi.encode(bytes32("ETH/USD"))
        );
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(int224(2000 * 1e18), uint32(block.timestamp - 1 hours))
        );

        // Mock the API3 proxy data for WBTC/USD
        vm.mockCall(
            DAPI_PROXY_WBTC_USD, abi.encodeWithSelector(IProxy.dapiName.selector), abi.encode(bytes32("WBTC/USD"))
        );
        vm.mockCall(
            DAPI_PROXY_WBTC_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(int224(42_000 * 1e18), uint32(block.timestamp - 1 hours))
        );

        // Add assets
        adapter.addAsset(WETH, "ETH/USD", DAPI_PROXY_ETH_USD, 4 hours, true);

        adapter.addAsset(WBTC, "WBTC/USD", DAPI_PROXY_WBTC_USD, 4 hours, true);
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        // Setup
        vm.startPrank(address(this));
        adapter.addAsset(WETH, "ETH/USD", DAPI_PROXY_ETH_USD, 4 hours, true);
        vm.stopPrank();

        // Get price
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertFalse(priceData.hadError);
        assertTrue(priceData.inUSD);
        assertGt(priceData.price, 0);
    }

    function testReturnsCorrectPrice_WBTC_USD() public view {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WBTC, true);

        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        assertEq(priceData.inUSD, true, "Price should be in USD");
    }

    function testPriceError_NegativePrice() public {
        // Create a test proxy with negative price
        vm.mockCall(
            DAPI_PROXY_ETH_USD, abi.encodeWithSelector(IProxy.read.selector), abi.encode(-1, uint32(block.timestamp))
        );

        ISharePriceOracle.PriceReturnData memory data = adapter.getPrice(WETH, true);
        assertEq(data.hadError, true, "Should error on negative price");
    }

    function testPriceError_StaleTimestamp() public {
        // Mock a stale timestamp
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(100, uint32(block.timestamp - 5 hours))
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, true, "Should error on stale timestamp");
    }

    function testPriceError_ExceedsMax() public {
        // Mock a huge price
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(type(int224).max, uint32(block.timestamp))
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, true, "Should error on price exceeding max");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
    }

    function testRevertAfterAssetRemove() public {
        // Get price before removal to ensure it works
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error before removal");
        assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

        // Remove the asset
        adapter.removeAsset(WETH);

        // Verify it reverts after removal
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.getPrice(WETH, true);
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        vm.expectRevert(Api3Adapter.Api3Adapter__InvalidHeartbeat.selector);
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            25 hours, // More than DEFAULT_HEART_BEAT
            true
        );
    }

    function testRevertAddAsset_DAPINameError() public {
        vm.expectRevert(Api3Adapter.Api3Adapter__DAPINameError.selector);
        adapter.addAsset(WETH, "WRONG_TICKER", DAPI_PROXY_ETH_USD, 1 hours, true);
    }

    function testCanAddSameAsset() public {
        // Should be able to add the same asset again
        adapter.addAsset(WETH, "ETH/USD", DAPI_PROXY_ETH_USD, 1 hours, true);

        // Verify it still works
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.removeAsset(address(0));
    }
}
