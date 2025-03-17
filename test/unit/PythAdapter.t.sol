// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { PythAdapter } from "../../src/adapters/Pyth.sol";
import { SharePriceOracle } from "../../src/SharePriceOracle.sol";
import { IPyth } from "../../src/interfaces/pyth/IPyth.sol";
import { PythStructs } from "../../src/interfaces/pyth/PythStructs.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";
import "forge-std/console.sol";

contract PythAdapterTest is Test {
    // Constants
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;

    // Pyth constants
    address constant PYTH_CONTRACT = 0x8250f4aF4B972684F7b336503E2D6dFeDeB1487a;
    bytes32 constant ETH_USD_PRICE_ID = 0xff61491a931112ddf1bd8147cd1b641375f79f5825126d665480874634fd0ace;
    bytes32 constant BTC_USD_PRICE_ID = 0xe62df6c8b4a85fe1a67db44dc12de5db330f7ac66b72dc658afedf0f4a415b43;

    uint32 constant HEARTBEAT = 3600; // 1 hour
    uint32 constant MAX_AGE = 60; // 60 seconds

    PythAdapter public adapter;
    SharePriceOracle public router;

    function setUp() public {
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(rpcUrl);

        router = new SharePriceOracle(address(this));

        adapter = new PythAdapter(address(this), address(this), address(router), PYTH_CONTRACT);

        adapter.addAsset(WETH, ETH_USD_PRICE_ID, HEARTBEAT, MAX_AGE, true);

        adapter.addAsset(WBTC, BTC_USD_PRICE_ID, HEARTBEAT, MAX_AGE, true);

        router.setLocalAssetConfig(WETH, address(adapter), address(adapter), 0, false);
        router.setLocalAssetConfig(WBTC, address(adapter), address(adapter), 0, false);

        _mockPythData();
    }

    function _mockPythData() internal {
        PythStructs.Price memory ethPrice = PythStructs.Price({
            price: 200_000_000_000,
            conf: 5_000_000,
            expo: -8,
            publishTime: uint64(block.timestamp - 10)
        });

        PythStructs.Price memory btcPrice = PythStructs.Price({
            price: 4_200_000_000_000,
            conf: 10_000_000,
            expo: -8,
            publishTime: uint64(block.timestamp - 15)
        });

        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ETH_USD_PRICE_ID, MAX_AGE),
            abi.encode(ethPrice)
        );

        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, BTC_USD_PRICE_ID, MAX_AGE),
            abi.encode(btcPrice)
        );

        vm.mockCall(PYTH_CONTRACT, abi.encodeWithSelector(IPyth.getUpdateFee.selector), abi.encode(0));
    }

    function testGetPrice_ETH_USD() public {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertEq(priceData.price, 2000e18, "Price should be $2000 normalized to 18 decimals");

        emit log_named_uint("WETH/USD Price", priceData.price);
    }

    function testGetPrice_BTC_USD() public {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WBTC, true);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertEq(priceData.price, 42_000e18, "Price should be $42000 normalized to 18 decimals");

        emit log_named_uint("WBTC/USD Price", priceData.price);
    }

    function testGetPrice_ETH_ETH() public {
        PythStructs.Price memory ethEthPrice =
            PythStructs.Price({ price: 100_000_000, conf: 0, expo: -8, publishTime: uint64(block.timestamp - 5) });

        bytes32 ethEthPriceId = bytes32(uint256(keccak256("WETH-WETH")));
        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ethEthPriceId, MAX_AGE),
            abi.encode(ethEthPrice)
        );

        adapter.addAsset(
            WETH,
            ethEthPriceId,
            HEARTBEAT,
            MAX_AGE,
            false // not in USD, in WETH
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, false);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertFalse(priceData.inUSD, "Price should be in WETH");
        assertEq(priceData.price, 1e18, "Price should be 1.0 WETH normalized to 18 decimals");

        emit log_named_uint("WETH/WETH Price", priceData.price);
    }

    function testPriceFallback_AlternateConfig() public {
        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WBTC, false);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertTrue(priceData.inUSD, "Price should indicate it fell back to USD");
        assertEq(priceData.price, 42_000e18, "Price should be $42000 normalized to 18 decimals");

        emit log_named_uint("WBTC fallback price", priceData.price);
    }

    function testPriceError_StalePrice() public {
        // Create a mock stale Pyth price
        PythStructs.Price memory stalePrice = PythStructs.Price({
            price: 200_000_000_000,
            conf: 5_000_000,
            expo: -8,
            publishTime: uint64(block.timestamp - HEARTBEAT - 1)
        });

        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ETH_USD_PRICE_ID, MAX_AGE),
            abi.encode(stalePrice)
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertTrue(priceData.hadError, "Price should have an error due to staleness");
    }

    function testPriceError_NegativePrice() public {
        PythStructs.Price memory negativePrice = PythStructs.Price({
            price: -200_000_000_000,
            conf: 5_000_000,
            expo: -8,
            publishTime: uint64(block.timestamp - 10)
        });

        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ETH_USD_PRICE_ID, MAX_AGE),
            abi.encode(negativePrice)
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertTrue(priceData.hadError, "Price should have an error due to negative price");
    }

    function testPriceError_PythException() public {
        vm.mockCallRevert(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ETH_USD_PRICE_ID, MAX_AGE),
            "Pyth error"
        );

        ISharePriceOracle.PriceReturnData memory priceData = adapter.getPrice(WETH, true);

        assertTrue(priceData.hadError, "Price should have an error due to Pyth exception");
    }

    function testRevertGetPrice_AssetNotSupported() public {
        vm.expectRevert(abi.encodeWithSelector(PythAdapter.PythAdapter__AssetNotSupported.selector, address(0xdead)));
        adapter.getPrice(address(0xdead), true);
    }

    function testGetPrice_AfterAssetRemoved() public {
        ISharePriceOracle.PriceReturnData memory priceDataBefore = adapter.getPrice(WETH, true);
        assertFalse(priceDataBefore.hadError, "Price should not have an error before removal");

        adapter.removeAsset(WETH);

        vm.expectRevert(abi.encodeWithSelector(PythAdapter.PythAdapter__AssetNotSupported.selector, WETH));
        adapter.getPrice(WETH, true);
    }

    function testUpdateAndGetPrice() public {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = "fake update data";

        vm.mockCall(PYTH_CONTRACT, abi.encodeWithSelector(IPyth.getUpdateFee.selector, updateData), abi.encode(1e15));

        vm.mockCall(PYTH_CONTRACT, abi.encodeWithSelector(IPyth.updatePriceFeeds.selector), abi.encode());

        ISharePriceOracle.PriceReturnData memory priceData =
            adapter.updateAndGetPrice{ value: 1e15 }(WETH, true, updateData);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertTrue(priceData.inUSD, "Price should be in USD");
        assertEq(priceData.price, 2000e18, "Price should be $2000 normalized to 18 decimals");
    }

    function testRevertAddAsset_InvalidHeartbeat() public {
        uint32 invalidHeartbeat = adapter.DEFAULT_HEARTBEAT() + 1;
        vm.expectRevert(abi.encodeWithSelector(PythAdapter.PythAdapter__InvalidHeartbeat.selector, invalidHeartbeat));
        adapter.addAsset(USDC, bytes32(0), invalidHeartbeat, MAX_AGE, true);
    }

    function testRevertAddAsset_InvalidMaxAge() public {
        uint32 invalidMaxAge = adapter.DEFAULT_MAX_AGE() + 1;
        vm.expectRevert(abi.encodeWithSelector(PythAdapter.PythAdapter__InvalidMaxAge.selector, invalidMaxAge));
        adapter.addAsset(USDC, bytes32(0), HEARTBEAT, invalidMaxAge, true);
    }

    function testBothUSDAndETHPriceConfigurations() public {
        bytes32 ethEthPriceId = bytes32(uint256(keccak256("WETH-WETH")));

        PythStructs.Price memory ethEthPrice =
            PythStructs.Price({ price: 100_000_000, conf: 0, expo: -8, publishTime: uint64(block.timestamp - 5) });

        vm.mockCall(
            PYTH_CONTRACT,
            abi.encodeWithSelector(IPyth.getPriceNoOlderThan.selector, ethEthPriceId, MAX_AGE),
            abi.encode(ethEthPrice)
        );

        adapter.addAsset(
            WETH,
            ethEthPriceId,
            HEARTBEAT,
            MAX_AGE,
            false // in WETH
        );

        ISharePriceOracle.PriceReturnData memory usdPriceData = adapter.getPrice(WETH, true);
        assertFalse(usdPriceData.hadError, "USD price should not have an error");
        assertTrue(usdPriceData.inUSD, "Price should be in USD");
        assertEq(usdPriceData.price, 2000e18, "Price should be $2000");

        ISharePriceOracle.PriceReturnData memory ethPriceData = adapter.getPrice(WETH, false);
        assertFalse(ethPriceData.hadError, "WETH price should not have an error");
        assertFalse(ethPriceData.inUSD, "Price should be in WETH");
        assertEq(ethPriceData.price, 1e18, "Price should be 1.0 WETH");
    }

    function testUpdatePriceWithZeroUpdateData() public {
        bytes[] memory emptyUpdateData = new bytes[](0);

        ISharePriceOracle.PriceReturnData memory priceData =
            adapter.updateAndGetPrice{ value: 0 }(WETH, true, emptyUpdateData);

        assertFalse(priceData.hadError, "Price should not have an error");
        assertEq(priceData.price, 2000e18, "Price should be $2000 normalized to 18 decimals");
    }

    function testReceiveFunction() public {
        payable(address(adapter)).transfer(1 ether);

        assertEq(address(adapter).balance, 1 ether, "Adapter should have received 1 ETH");
    }
}
