// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import { Test } from "forge-std/Test.sol";
// import { BalancerAdapter } from "../../src/adapters/Balancer.sol";
// import { SharePriceRouter } from "../../src/SharePriceRouter.sol";
// import { IBalancerWeightedPool } from "../../src/interfaces/balancer/IBalancerWeightedPool.sol";
// import { IBalancerVault } from "../../src/interfaces/balancer/IBalancerVault.sol";
// import { ISharePriceRouter } from "../../src/interfaces/ISharePriceRouter.sol";

// contract BalancerAdapterTest is Test {
//     // Constants for BASE network
//     address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
//     address constant WETH = 0x4200000000000000000000000000000000000006;
//     address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;

//     // Real Balancer addresses on Base
//     address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

//     // WETH/cbETH 50-50 Weighted Pool
//     address constant WETH_cbETH_POOL = 0xFb4C2E6E6e27B5b4a07a36360C89EDE29bB3c9B6;
//     address constant WETH_cbETH_BPT = 0x4200000000000000000000000000000000000006;

//     // Test contracts
//     BalancerAdapter public adapter;
//     SharePriceRouter public router;

//     function setUp() public {
//         string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
//         vm.createSelectFork(baseRpcUrl);

//         // Deploy router
//         router = new SharePriceRouter(
//             address(this) // admin
//         );

//         // Deploy adapter
//         adapter = new BalancerAdapter(
//             address(this), // admin
//             address(router), // oracle
//             address(router), // router
//             BALANCER_VAULT,
//             USDC
//         );

//         // Add adapter to router
//         router.setLocalAssetConfig(WETH_cbETH_BPT, address(adapter), WETH_cbETH_POOL, 0, false);

//         // Grant ORACLE_ROLE to test contract
//         adapter.grantRole(address(this), uint256(adapter.ORACLE_ROLE()));

//         // Add assets to adapter
//         adapter.addAsset(WETH_cbETH_BPT, WETH_cbETH_POOL, 4 hours);
//     }

//     function testReturnsCorrectPrice_WETH_cbETH_BPT() public {
//         ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH_cbETH_BPT, true);

//         assertFalse(priceData.hadError, "Price should not have error");
//         assertTrue(priceData.inUSD, "Price should be in USD");
//         assertGt(priceData.price, 0, "Price should be greater than 0");

//         emit log_named_uint("WETH-cbETH BPT Price", priceData.price);
//     }

//     function testPriceError_StaleTimestamp() public {
//         // Mock stale timestamp
//         vm.mockCall(
//             WETH_cbETH_POOL,
//             abi.encodeWithSelector(IBalancerWeightedPool.getLastInvariantCalculationTimestamp.selector),
//             abi.encode(block.timestamp - 5 hours)
//         );

//         vm.expectRevert(BalancerAdapter.BalancerAdapter__StalePrice.selector);
//         adapter.getPrice(WETH_cbETH_BPT, true);
//     }

//     function testPriceError_ZeroPrice() public {
//         vm.mockCall(
//             WETH_cbETH_POOL,
//             abi.encodeWithSelector(IBalancerWeightedPool.getLastInvariant.selector),
//             abi.encode(0)
//         );

//         vm.expectRevert(BalancerAdapter.BalancerAdapter__PriceError.selector);
//         adapter.getPrice(WETH_cbETH_BPT, true);
//     }

//     function testRevertGetPrice_AssetNotSupported() public {
//         vm.expectRevert(BalancerAdapter.BalancerAdapter__AssetNotSupported.selector);
//         adapter.getPrice(address(0), true);
//     }

//     function testRevertAfterAssetRemove() public {
//         ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH_cbETH_BPT, true);
//         assertFalse(priceData.hadError, "Price should not have error before removal");
//         assertGt(priceData.price, 0, "Price should be greater than 0 before removal");

//         adapter.removeAsset(WETH_cbETH_BPT);

//         vm.expectRevert(BalancerAdapter.BalancerAdapter__AssetNotSupported.selector);
//         adapter.getPrice(WETH_cbETH_BPT, true);
//     }

//     function testRevertAddAsset_InvalidHeartbeat() public {
//         vm.expectRevert(BalancerAdapter.BalancerAdapter__InvalidHeartbeat.selector);
//         adapter.addAsset(
//             WETH_cbETH_BPT,
//             WETH_cbETH_POOL,
//             25 hours
//         );
//     }

//     function testRevertAddAsset_InvalidPool() public {

//         vm.mockCall(
//             WETH_cbETH_POOL,
//             abi.encodeWithSelector(IBalancerWeightedPool.getNormalizedWeights.selector),
//             abi.encode(bytes(""))
//         );
//         vm.expectRevert(BalancerAdapter.BalancerAdapter__InvalidPool.selector);
//         adapter.addAsset(WETH_cbETH_BPT, WETH_cbETH_POOL, 1 hours);
//     }

//     function testCanAddSameAsset() public {
//         adapter.addAsset(WETH_cbETH_BPT, WETH_cbETH_POOL, 1 hours);

//         ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH_cbETH_BPT, true);
//         assertFalse(priceData.hadError, "Price should not have error");
//         assertGt(priceData.price, 0, "Price should be greater than 0");

//         emit log_named_uint("WETH-USDC BPT Price after re-add", priceData.price);
//     }

//     function testRevertRemoveAsset_AssetNotSupported() public {
//         vm.expectRevert(BalancerAdapter.BalancerAdapter__AssetNotSupported.selector);
//         adapter.removeAsset(address(0));
//     }

//     function testPriceInETH() public {
//         ISharePriceRouter.PriceReturnData memory priceData = adapter.getPrice(WETH_cbETH_BPT, false);

//         assertFalse(priceData.hadError, "Price should not have error");
//         assertFalse(priceData.inUSD, "Price should be in ETH");
//         assertGt(priceData.price, 0, "Price should be greater than 0");

//         emit log_named_uint("WETH-USDC BPT Price in ETH", priceData.price);
//     }
// }
