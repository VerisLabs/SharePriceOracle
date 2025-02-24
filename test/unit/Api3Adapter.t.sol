// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import "forge-std/console.sol";
import { Api3Adaptor } from "../../src/adapters/Api3.sol";
import { IProxy } from "../../src/interfaces/api3/IProxy.sol";
import { PriceReturnData } from "../../src/interfaces/IOracleAdaptor.sol";
import { IOracleRouter } from "../../src/interfaces/IOracleRouter.sol";
import { SharePriceRouter } from "../../src/SharePriceRouter.sol";

contract MockRouter {
    function notifyFeedRemoval(address) external pure {}
}

contract Api3AdapterTest is Test {
    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    
    // API3 price feed addresses on BASE
    address constant DAPI_PROXY_ETH_USD = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address constant DAPI_PROXY_WBTC_USD = 0x041a131Fa91Ad61dD85262A42c04975986580d50;

    // Test contracts
    Api3Adaptor public adapter;
    SharePriceRouter public oracle;
    MockRouter public router;
    
    function setUp() public {
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy mock router
        router = new MockRouter();

        // Deploy oracle
        oracle = new SharePriceRouter(
            address(this),  // admin
            DAPI_PROXY_ETH_USD,  // ETH/USD feed
            USDC,
            WBTC,
            WETH
        );

        // Deploy adapter
        adapter = new Api3Adaptor(
            address(this),  // admin
            address(oracle),  // oracle
            address(router),  // router
            WETH  // WETH address
        );

        // Add adapter to oracle
        oracle.addAdapter(address(adapter), 1);

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Mock the API3 proxy data for WBTC/USD
        vm.mockCall(
            DAPI_PROXY_WBTC_USD,
            abi.encodeWithSelector(IProxy.dapiName.selector),
            abi.encode(bytes32("WBTC/USD"))
        );
        vm.mockCall(
            DAPI_PROXY_WBTC_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(int224(42000 * 1e18), uint32(block.timestamp - 1 hours))
        );

        // Add assets
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            4 hours,
            true
        );

        adapter.addAsset(
            WBTC,
            "WBTC/USD",
            DAPI_PROXY_WBTC_USD,
            4 hours,
            true
        );
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        // Setup
        vm.startPrank(address(this));
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            4 hours,
            true
        );
        vm.stopPrank();

        // Get price
        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        
        assertFalse(priceData.hadError);
        assertTrue(priceData.inUSD);
        assertGt(priceData.price, 0);

        console.log("ETH/USD Price:", priceData.price);
    }

    function testReturnsCorrectPrice_WBTC_USD() public {
        PriceReturnData memory priceData = adapter.getPrice(WBTC, true, false);
        
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        assertEq(priceData.inUSD, true, "Price should be in USD");
    }

    function testPriceError_NegativePrice() public {
        // Create a test proxy with negative price
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(-1, uint32(block.timestamp))
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        assertEq(priceData.hadError, true, "Should error on negative price");
    }

    function testPriceError_StaleTimestamp() public {
        // Mock a stale timestamp
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(100, uint32(block.timestamp - 5 hours))
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        assertEq(priceData.hadError, true, "Should error on stale timestamp");
    }

    function testPriceError_ExceedsMax() public {
        // Mock a huge price
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(type(int224).max, uint32(block.timestamp))
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        assertEq(priceData.hadError, true, "Should error on price exceeding max");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__AssetIsNotSupported.selector);
        adapter.getPrice(USDC, true, false);
    }

    function testRevertAfterAssetRemove() public {
        // Get price before removal to ensure it works
        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        assertEq(priceData.hadError, false, "Price should not have error before removal");
        assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

        // Remove the asset
        adapter.removeAsset(WETH);

        // Verify it reverts after removal
        vm.expectRevert(Api3Adaptor.Api3Adaptor__AssetIsNotSupported.selector);
        adapter.getPrice(WETH, true, false);
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__InvalidHeartbeat.selector);
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            25 hours, // More than DEFAULT_HEART_BEAT
            true
        );
    }

    function testRevertAddAsset_DAPINameError() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__DAPINameError.selector);
        adapter.addAsset(
            WETH,
            "WRONG_TICKER",
            DAPI_PROXY_ETH_USD,
            1 hours,
            true
        );
    }

    function testCanAddSameAsset() public {
        // Get current adapter data
        (
            IProxy proxyFeed,
            bytes32 dapiNameHash,
            bool isConfigured,
            uint256 heartbeat,
            uint256 max,
            uint256 min
        ) = adapter.adaptorDataUSD(WETH);

        // Should be able to add the same asset again
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            1 hours,
            true
        );

        // Verify it still works
        PriceReturnData memory priceData = adapter.getPrice(WETH, true, false);
        assertEq(priceData.hadError, false, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.expectRevert(Api3Adaptor.Api3Adaptor__AssetIsNotSupported.selector);
        adapter.removeAsset(address(0));
    }
} 