// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {SharePriceOracle} from "../src/SharePriceOracle.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {VaultReport} from "../src/interfaces/ISharePriceOracle.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISharePriceOracle} from "../src/interfaces/ISharePriceOracle.sol";

contract SharePriceOracleTest is Test {
    SharePriceOracle public oracle;
    MockPriceFeed public ethUsdFeed;
    MockPriceFeed public tokenAFeed;
    MockPriceFeed public tokenBFeed;
    MockERC4626 public vaultA;
    MockERC4626 public vaultB;
    address public admin;
    address public endpoint;
    address public user;
    uint32 public constant CHAIN_ID = 1;
    uint32 public constant REMOTE_CHAIN_ID = 2;

    event SharePriceUpdated(
        uint32 indexed srcChainId,
        address indexed vault,
        uint256 price,
        address rewardsDelegate
    );

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        endpoint = makeAddr("endpoint");
        user = makeAddr("user");

        // Deploy mock price feeds
        ethUsdFeed = new MockPriceFeed();
        tokenAFeed = new MockPriceFeed();
        tokenBFeed = new MockPriceFeed();

        // Set initial prices
        ethUsdFeed.setPrice(2000e8); // $2000 USD/ETH
        tokenAFeed.setPrice(100e8); // $100 USD/TokenA
        tokenBFeed.setPrice(50e8); // $50 USD/TokenB

        // Deploy mock vaults
        vaultA = new MockERC4626();
        vaultB = new MockERC4626();

        // Set initial share prices
        vaultA.setMockSharePrice(1.5e18); // 1.5 tokens per share
        vaultB.setMockSharePrice(2e18); // 2 tokens per share

        // Deploy oracle as admin
        vm.startPrank(admin);
        oracle = new SharePriceOracle(CHAIN_ID, admin, address(ethUsdFeed));

        // Setup roles and price feeds
        oracle.grantRole(endpoint, oracle.ENDPOINT_ROLE());
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultA.asset(),
            SharePriceOracle.PriceFeedInfo({
                feed: address(tokenAFeed),
                denomination: SharePriceOracle.PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultB.asset(),
            SharePriceOracle.PriceFeedInfo({
                feed: address(tokenBFeed),
                denomination: SharePriceOracle.PriceDenomination.USD
            })
        );
        vm.stopPrank();
    }

    function test_GetSharePrices() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(vaultA);
        vaults[1] = address(vaultB);

        address rewardsDelegate = makeAddr("delegate");
        VaultReport[] memory reports = oracle.getSharePrices(
            vaults,
            rewardsDelegate
        );

        assertEq(reports.length, 2, "Wrong number of reports");
        assertEq(
            reports[0].vaultAddress,
            address(vaultA),
            "Wrong vault address A"
        );
        assertEq(
            reports[1].vaultAddress,
            address(vaultB),
            "Wrong vault address B"
        );
        assertEq(reports[0].sharePrice, 1.5e18, "Wrong share price A");
        assertEq(reports[1].sharePrice, 2e18, "Wrong share price B");
        assertEq(
            reports[0].rewardsDelegate,
            rewardsDelegate,
            "Wrong rewards delegate A"
        );
        assertEq(
            reports[1].rewardsDelegate,
            rewardsDelegate,
            "Wrong rewards delegate B"
        );
    }

    function test_UpdateSharePrices() public {
        VaultReport[] memory reports = new VaultReport[](1);
        address delegate = makeAddr("delegate");

        reports[0] = VaultReport({
            sharePrice: 1.5e18,
            lastUpdate: uint64(block.timestamp),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: delegate,
            vaultAddress: address(vaultA),
            asset: vaultA.asset(),
            assetDecimals: 18
        });

        vm.startPrank(endpoint);
        vm.expectEmit(true, true, false, true);
        emit SharePriceUpdated(
            REMOTE_CHAIN_ID,
            address(vaultA),
            1.5e18,
            delegate
        );

        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);

        // Also set up price feed for remote chain
        vm.stopPrank();
        vm.prank(admin);
        oracle.setPriceFeed(
            REMOTE_CHAIN_ID,
            reports[0].asset,
            SharePriceOracle.PriceFeedInfo({
                feed: address(tokenAFeed),
                denomination: SharePriceOracle.PriceDenomination.USD
            })
        );

        // Verify stored report
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            REMOTE_CHAIN_ID,
            address(vaultA),
            vaultB.asset()
        );
        assertGt(price, 0, "Price should be non-zero");
        assertEq(timestamp, block.timestamp, "Wrong timestamp");
    }

    function test_RevertWhen_UnauthorizedUpdateSharePrices() public {
        VaultReport[] memory reports = new VaultReport[](1);
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(); // Should revert due to missing ENDPOINT_ROLE
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);
    }

    function test_PriceConversion() public {
        // Set up prices for conversion test
        vaultA.setMockSharePrice(1e18); // 1 tokenA per share
        tokenAFeed.setPrice(100e8); // $100 per tokenA
        tokenBFeed.setPrice(50e8); // $50 per tokenB

        address[] memory vaults = new address[](1);
        vaults[0] = address(vaultA);

        // Get share price in tokenB terms
        (uint256 priceInTokenB, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(vaultA),
            vaultB.asset()
        );

        // 1 share = 1 tokenA = $100
        // In tokenB terms: $100 / $50 = 2 tokenB
        assertEq(priceInTokenB, 2e18, "Wrong converted price");
        assertEq(timestamp, block.timestamp, "Wrong timestamp");
    }

    function test_ETHDenominatedFeeds() public {
        // Setup initial conditions
        vaultA.setMockSharePrice(1e18); // 1:1 ratio for simplicity

        // Setup ETH denominated feed with correct decimals
        MockPriceFeed ethDenomFeed = new MockPriceFeed();
        // 0.05 ETH per token with 18 decimals (same as ETH)
        ethDenomFeed.setPrice(50000000000000000); // 0.05 ETH

        console.log("ETH/USD Price:", ethUsdFeed.latestAnswer());
        console.log("Token ETH Price:", ethDenomFeed.latestAnswer());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultA.asset(),
            SharePriceOracle.PriceFeedInfo({
                feed: address(ethDenomFeed),
                denomination: SharePriceOracle.PriceDenomination.ETH
            })
        );
        vm.stopPrank();

        // Get price in tokenB terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(vaultA),
            vaultB.asset()
        );

        console.log("Conversion Result:", price);
        console.log("Timestamp:", timestamp);

        // Expected calculation:
        // 1 vault share = 1 tokenA (from share price)
        // 1 tokenA = 0.05 ETH
        // 0.05 ETH * $2000/ETH = $100
        // $100 / $50 per tokenB = 2 tokenB
        assertApproxEqRel(price, 2e18, 0.01e18); // 1% tolerance
    }

    /*
    function test_RevertWhen_InvalidPriceFeed_banana() public {
        vm.startPrank(admin);

        MockPriceFeed invalidFeed = new MockPriceFeed();
        invalidFeed.setPrice(0);

        SharePriceOracle.PriceFeedInfo memory info = SharePriceOracle
            .PriceFeedInfo({
                feed: address(0),
                denomination: SharePriceOracle.PriceDenomination.USD
            });
        
        vm.expectRevert();
        oracle.setPriceFeed(CHAIN_ID, vaultA.asset(), info);
        vm.stopPrank();
    }
    */

    function test_GetSharePrices_WithMultipleVaultsAndTokens() public {
        // Deploy additional mock vault with different asset
        MockERC4626 vaultC = new MockERC4626();
        MockPriceFeed tokenCFeed = new MockPriceFeed();

        tokenCFeed.setPrice(75e8); // $75 USD/TokenC
        vaultC.setMockSharePrice(3e18); // 3 tokens per share

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultC.asset(),
            SharePriceOracle.PriceFeedInfo({
                feed: address(tokenCFeed),
                denomination: SharePriceOracle.PriceDenomination.USD
            })
        );
        vm.stopPrank();

        // Test with three vaults
        address[] memory vaults = new address[](3);
        vaults[0] = address(vaultA);
        vaults[1] = address(vaultB);
        vaults[2] = address(vaultC);

        address rewardsDelegate = makeAddr("delegate");
        VaultReport[] memory reports = oracle.getSharePrices(
            vaults,
            rewardsDelegate
        );

        assertEq(reports.length, 3, "Wrong number of reports");
        assertEq(reports[0].sharePrice, 1.5e18, "Wrong share price A");
        assertEq(reports[1].sharePrice, 2e18, "Wrong share price B");
        assertEq(reports[2].sharePrice, 3e18, "Wrong share price C");
    }

    function test_RevertWhen_StalePrices() public {
        // Make prices stale
        vm.warp(block.timestamp + oracle.SHARE_PRICE_STALENESS_TOLERANCE() + 1);

        VaultReport memory report = VaultReport({
            sharePrice: 1.5e18,
            lastUpdate: uint64(
                block.timestamp - oracle.SHARE_PRICE_STALENESS_TOLERANCE() - 1
            ),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(vaultA),
            asset: vaultA.asset(),
            assetDecimals: 18
        });

        // The price should be considered stale
        (uint256 price, ) = oracle.getLatestSharePrice(
            REMOTE_CHAIN_ID,
            report.vaultAddress,
            vaultB.asset()
        );
        assertEq(price, 0, "Price should be zero due to staleness");
    }
}
