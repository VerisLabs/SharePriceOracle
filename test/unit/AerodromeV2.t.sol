// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Chainlink.sol";
import "../../src/adapters/aerodrome/AerodromeV2.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
// import { IAerodromeV1Pool } from "../../src/interfaces/aerodrome/IAerodromeV1Pool.sol";
import { ISharePriceRouter } from "../../src/interfaces/ISharePriceRouter.sol";
import { AerodromeBaseAdapter } from "src/adapters/aerodrome/AerodromeBaseAdapter.sol";

contract TestAerodromeV2Adapter is Test {
    address private CHAINLINK_PRICE_FEED_USDC = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address private AERO_POOL_cbBTC_USDC = 0x4e962BB3889Bf030368F56810A9c96B83CB3E778;

    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // Test contracts
    address public admin;
    AerodromeV2Adapter public adapter;
    ChainlinkAdapter public chainlinkAdapter;
    SharePriceRouter public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceRouter(address(this));


        adapter = new AerodromeV2Adapter(
            address(this),  // admin
            address(router),  // oracle
            address(router)  // router
        );

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Deploy adapter
        chainlinkAdapter = new ChainlinkAdapter(
            address(this),  // admin
            address(router),  // oracle
            address(router)  // router
        );
        // Grant ORACLE_ROLE to test contract
        chainlinkAdapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        chainlinkAdapter.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        // Configure price feeds in router
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), CHAINLINK_PRICE_FEED_USDC, 0, true);
        router.setLocalAssetConfig(cbBTC, address(adapter), AERO_POOL_cbBTC_USDC, 0, true);

        AerodromeV2Adapter.AdapterData memory data;
        data.pool = AERO_POOL_cbBTC_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 8;
        data.baseTokenDecimals = 6;
       
        adapter.addAsset(cbBTC, data);

    }

    function testReturnsCorrectPrice() public {

        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(cbBTC, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("cbBTC/USD Price", priceData.price);
    }
        

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();
        adapter.removeAsset(cbBTC);

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__AssetIsNotSupported.selector);
        adapter.getPrice(cbBTC, true);
    }
    
    function testRevertAddAsset__InvalidPool() public {

        AerodromeV2Adapter.AdapterData memory data;
        data.pool = cbBTC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 8;
        data.baseTokenDecimals = 6;

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__InvalidPoolAddress.selector);
        adapter.addAsset(cbBTC, data);
    }
    
    function testRevertAddAsset__InvalidAsset() public {
        AerodromeV2Adapter.AdapterData memory data;
        data.pool = AERO_POOL_cbBTC_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 8;
        data.baseTokenDecimals = 6;

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__InvalidAsset.selector);
        adapter.addAsset(USDC, data);
    }
    
    
    function testUpdateAsset() public {

        AerodromeV2Adapter.AdapterData memory data;
        data.pool = AERO_POOL_cbBTC_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 8;
        data.baseTokenDecimals = 6;

        adapter.addAsset(cbBTC, data);
        adapter.addAsset(cbBTC, data);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__AssetIsNotSupported.selector);
        adapter.removeAsset(USDC);
    }

}