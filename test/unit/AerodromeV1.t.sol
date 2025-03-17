// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/adapters/Chainlink.sol";
import "../../src/adapters/aerodrome/AerodromeV1.sol";
import "../../src/SharePriceOracle.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE } from "../utils/AddressBook.sol";
import { BaseOracleAdapter } from "../../src/libs/base/BaseOracleAdapter.sol";
import { IAerodromeV1Pool } from "../../src/interfaces/aerodrome/IAerodromeV1Pool.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";
import { AerodromeBaseAdapter } from "src/adapters/aerodrome/AerodromeBaseAdapter.sol";

contract TestAerodromeV1Adapter is Test {
    address private CHAINLINK_PRICE_FEED_USDC = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address private AERO_POOL_DAI_USDC = 0x67b00B46FA4f4F24c03855c5C8013C0B938B3eEc;

    // Constants for BASE network
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

    // Test contracts
    address public admin;
    AerodromeV1Adapter public adapter;
    ChainlinkAdapter public chainlinkAdapter;
    SharePriceOracle public router;

    function setUp() public {
        admin = makeAddr("admin");
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Deploy router with admin
        router = new SharePriceOracle(address(this));

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
    }

    function testReturnsCorrectPrice() public {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(DAI, true);

        assertFalse(priceData.hadError, "Price should not have error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertGt(priceData.price, 0, "Price should be greater than 0");

        // Log the actual price for verification
        emit log_named_uint("DAI/USD Price", priceData.price);
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
