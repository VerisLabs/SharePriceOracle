// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Api3.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { IProxy } from "../../src/interfaces/api3/IProxy.sol";
import { ISharePriceRouter, PriceReturnData } from "../../src/interfaces/ISharePriceRouter.sol";

contract Api3AdapterTest is Test {
    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    
    // API3 price feed addresses on BASE
    address constant DAPI_PROXY_ETH_USD = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
    address constant DAPI_PROXY_WBTC_USD = 0x041a131Fa91Ad61dD85262A42c04975986580d50;

    // Test contracts
    address public admin;
    Api3Adapter public adapter;
    SharePriceRouter public router;
    
    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceRouter(admin);

        vm.startPrank(admin);
        // Set sequencer
        router.setSequencer(DAPI_PROXY_ETH_USD);

        // Deploy adapter
        adapter = new Api3Adapter(
            admin,  // admin
            admin,  // oracle
            address(router),  // router
            WETH  // WETH address
        );

        // Configure price feeds in router
        router.setLocalAssetConfig(WETH, 0, DAPI_PROXY_ETH_USD, true);
        router.setLocalAssetConfig(WBTC, 0, DAPI_PROXY_WBTC_USD, true);

        // Grant ORACLE_ROLE to admin
        adapter.grantRole(admin, uint256(adapter.ORACLE_ROLE()));

        // Mock the API3 proxy data for ETH/USD
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.dapiName.selector),
            abi.encode(bytes32("ETH/USD"))
        );
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(int224(2000 * 1e18), uint32(block.timestamp - 1 hours))
        );

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

        // Add assets to adapter
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
        vm.stopPrank();
    }

    function testReturnsCorrectPrice_ETH_USD() public {
        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        
        assertFalse(priceData.hadError);
        assertTrue(priceData.inUSD);
        assertGt(priceData.price, 0);
    }

    function testReturnsCorrectPrice_WBTC_USD() public {
        PriceReturnData memory priceData = adapter.getPrice(WBTC, true);
        
        assertFalse(priceData.hadError);
        assertTrue(priceData.inUSD);
        assertGt(priceData.price, 0);
    }

    function testPriceError_NegativePrice() public {
        // Create a test proxy with negative price
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(-1, uint32(block.timestamp))
        );

        vm.expectRevert(Api3Adapter.Api3Adapter__InvalidPrice.selector);
        adapter.getPrice(WETH, true);
    }

    function testPriceError_StaleTimestamp() public {
        // Mock a stale timestamp
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(100, uint32(block.timestamp - 5 hours))
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertTrue(priceData.hadError, "Should error on stale timestamp");
    }

    function testPriceError_ExceedsMax() public {
        // Mock a huge price
        vm.mockCall(
            DAPI_PROXY_ETH_USD,
            abi.encodeWithSelector(IProxy.read.selector),
            abi.encode(type(int224).max, uint32(block.timestamp))
        );

        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertTrue(priceData.hadError, "Should error on price exceeding max");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.getPrice(USDC, true);
    }

    function testRevertAfterAssetRemove() public {
        // First get a valid price to confirm setup
        adapter.getPrice(WETH, true);

        // Remove the asset configuration by setting priority to 0
        vm.startPrank(admin);
        router.setLocalAssetConfig(WETH, 0, address(1), true);
        vm.stopPrank();

        // Expect revert when trying to get price for removed asset
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.getPrice(WETH, true);
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        vm.startPrank(admin);
        vm.expectRevert(Api3Adapter.Api3Adapter__InvalidHeartbeat.selector);
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            25 hours, // More than DEFAULT_HEART_BEAT
            true
        );
        vm.stopPrank();
    }

    function testRevertAddAsset_DAPINameError() public {
        vm.startPrank(admin);
        vm.expectRevert(Api3Adapter.Api3Adapter__DAPINameError.selector);
        adapter.addAsset(
            WETH,
            "WRONG_TICKER",
            DAPI_PROXY_ETH_USD,
            1 hours,
            true
        );
        vm.stopPrank();
    }

    function testCanAddSameAsset() public {
        vm.startPrank(admin);
        // Should be able to add the same asset again
        adapter.addAsset(
            WETH,
            "ETH/USD",
            DAPI_PROXY_ETH_USD,
            1 hours,
            true
        );

        // Verify it still works
        PriceReturnData memory priceData = adapter.getPrice(WETH, true);
        assertFalse(priceData.hadError, "Price should not have error");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        vm.stopPrank();
    }

    function testRevertRemoveAsset_AssetNotSupported() public {
        vm.startPrank(admin);
        vm.expectRevert(Api3Adapter.Api3Adapter__AssetNotSupported.selector);
        adapter.removeAsset(address(0));
        vm.stopPrank();
    }
} 
