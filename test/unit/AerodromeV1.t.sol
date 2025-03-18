// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Chainlink.sol";
import "../../src/adapters/aerodrome/AerodromeV1.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { IAerodromeV1Pool } from "../../src/interfaces/aerodrome/IAerodromeV1Pool.sol";
import { ISharePriceRouter } from "../../src/interfaces/ISharePriceRouter.sol";
import { AerodromeBaseAdapter } from "src/adapters/aerodrome/AerodromeBaseAdapter.sol";

contract TestAerodromeV1Adapter is Test {
    //Price Feed set1
    address private CHAINLINK_PRICE_FEED_USDC = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address private AERO_POOL_DAI_USDC = 0x67b00B46FA4f4F24c03855c5C8013C0B938B3eEc;

    //Price Feed set2
    address private AERO_POOL_WETH_CBBTC = 0x2578365B3dfA7FfE60108e181EFb79FeDdec2319;
    address constant cbBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    // Test contracts
    address public admin;
    AerodromeV1Adapter public adapter;
    ChainlinkAdapter public chainlinkAdapter;
    SharePriceRouter public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceRouter(address(this));

        adapter = new AerodromeV1Adapter(
            address(this), // admin
            address(router), // oracle
            address(router) // router
        );

        // Grant ORACLE_ROLE to test contract
        adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        // Deploy adapter
        chainlinkAdapter = new ChainlinkAdapter(
            address(this), // admin
            address(router), // oracle
            address(router) // router
        );
        // Grant ORACLE_ROLE to test contract
        chainlinkAdapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

        chainlinkAdapter.addAsset(USDC, CHAINLINK_PRICE_FEED_USDC, 0, true);

        // Configure price feeds in router
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), CHAINLINK_PRICE_FEED_USDC, 0, true);
        router.setLocalAssetConfig(DAI, address(adapter), AERO_POOL_DAI_USDC, 0, true);

        AerodromeV1Adapter.AdapterData memory data;
        data.pool = AERO_POOL_DAI_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 18;
        data.baseTokenDecimals = 6;

        adapter.addAsset(DAI, data);

        AerodromeV1Adapter.AdapterData memory data1;
        data1.pool = AERO_POOL_WETH_CBBTC;
        data1.baseToken = WETH;
        data1.quoteTokenDecimals = 8;
        data1.baseTokenDecimals = 18;
       
        adapter.addAsset(cbBTC, data1);

    }

    function testReturnsCorrectPrice() public {
        ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(DAI, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");
        // Log the actual price for verification
        emit log_named_uint("DAI/USD Price", priceData.price);


        ISharePriceRouter.PriceReturnData memory priceData1 = adapter.getPrice(cbBTC, false);

        assertFalse(priceData1.hadError, "Price should not have error");
        assertTrue(!priceData1.inUSD, "Price should not be in USD");
        assertGt(priceData1.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("cbBTC/WETH Price", priceData1.price);
    }
        

    function testRevertAfterAssetRemove() public {
        testReturnsCorrectPrice();
        adapter.removeAsset(DAI);

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__AssetIsNotSupported.selector);
        adapter.getPrice(DAI, true);
    }

    function testRevertAddAsset__InvalidPool() public {
        AerodromeV1Adapter.AdapterData memory data;
        data.pool = DAI;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 18;
        data.baseTokenDecimals = 6;

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__InvalidPoolAddress.selector);
        adapter.addAsset(DAI, data);
    }

    function testRevertAddAsset__InvalidAsset() public {
        AerodromeV1Adapter.AdapterData memory data;
        data.pool = AERO_POOL_DAI_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 18;
        data.baseTokenDecimals = 6;

        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__InvalidAsset.selector);
        adapter.addAsset(USDC, data);
    }

    function testUpdateAsset() public {
        AerodromeV1Adapter.AdapterData memory data;
        data.pool = AERO_POOL_DAI_USDC;
        data.baseToken = USDC;
        data.quoteTokenDecimals = 18;
        data.baseTokenDecimals = 6;

        adapter.addAsset(DAI, data);
        adapter.addAsset(DAI, data);
    }

    function testRevertRemoveAsset__AssetIsNotSupported() public {
        vm.expectRevert(AerodromeBaseAdapter.AerodromeAdapter__AssetIsNotSupported.selector);
        adapter.removeAsset(USDC);
    }
}
