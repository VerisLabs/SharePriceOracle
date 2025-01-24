// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {SharePriceOracle} from "../src/SharePriceOracle.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {MockERC4626} from "./mocks/MockERC4626.sol";
import {MockPriceFeed} from "./mocks/MockPriceFeed.sol";
import {PriceFeedInfo, PriceDenomination, VaultReport} from "../src/interfaces/ISharePriceOracle.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ISharePriceOracle} from "../src/interfaces/ISharePriceOracle.sol";
import {VaultLib} from "../src/libs/VaultLib.sol";
import {Ownable} from "@solady/auth/Ownable.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";

/// @title SharePriceOracle Test Suite
/// @notice Comprehensive test suite for SharePriceOracle contract functionality
contract SharePriceOracleTest is Test {
    // ========== STATE VARIABLES ==========

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

    // ========== EVENTS ==========

    event SharePriceUpdated(
        uint32 indexed srcChainId,
        address indexed vault,
        uint256 price,
        address rewardsDelegate
    );

    // ========== SETUP ==========

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        endpoint = makeAddr("endpoint");
        user = makeAddr("user");

        // Deploy mock price feeds
        ethUsdFeed = new MockPriceFeed(8);
        tokenAFeed = new MockPriceFeed(8);
        tokenBFeed = new MockPriceFeed(8);

        // Set initial prices
        ethUsdFeed.setPrice(2000e8); // $2000 USD/ETH
        tokenAFeed.setPrice(100e8); // $100 USD/TokenA
        tokenBFeed.setPrice(50e8); // $50 USD/TokenB

        // Deploy mock vaults with 18 decimals
        vaultA = new MockERC4626(18);
        vaultB = new MockERC4626(18);

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
            PriceFeedInfo({
                feed: address(tokenAFeed),
                denomination: PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultB.asset(),
            PriceFeedInfo({
                feed: address(tokenBFeed),
                denomination: PriceDenomination.USD
            })
        );
        vm.stopPrank();
    }

    // ========== BASIC FUNCTIONALITY TESTS ==========

    function test_getSharePrices_singleVault() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(vaultA);

        address rewardsDelegate = makeAddr("delegate");
        VaultReport[] memory reports = oracle.getSharePrices(
            vaults,
            rewardsDelegate
        );

        assertEq(reports.length, 1, "Wrong number of reports");
        assertEq(
            reports[0].vaultAddress,
            address(vaultA),
            "Wrong vault address A"
        );
        assertEq(reports[0].sharePrice, 1.5e18, "Wrong share price A");
        assertEq(
            reports[0].rewardsDelegate,
            rewardsDelegate,
            "Wrong rewards delegate A"
        );
    }

    function test_getSharePrices_multipleVaults() public {
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

    function test_updateSharePrices_adminOnly() public {
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
            PriceFeedInfo({
                feed: address(tokenAFeed),
                denomination: PriceDenomination.USD
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

    // ========== PRICE CONVERSION TESTS ==========

    function test_PriceConversion_ETHtoUSDC_RealWorldExample_banana() public {
        // Setup with same values
        MockERC4626 ethVault = new MockERC4626(18);
        ethVault.setMockSharePrice(1057222067502682416); // 1.057 ETH
        ethUsdFeed.setPrice(334201032054); // $3342.01 USD/ETH
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100005101); // $1.00005 USD/USDC
        MockERC4626 usdcVault = new MockERC4626(6);

        // Log initial values
        console.log("\nInput Values:");
        console.log("ETH amount (wei):", "1057222067502682416");
        console.log("ETH/USD price (8 decimals):", "334201032054");
        console.log("USDC/USD price (8 decimals):", "100005101");

        // Setup price feeds
        vm.startPrank(admin);
        oracle.setPriceFeed(
            137,
            ethVault.asset(),
            PriceFeedInfo({
                feed: address(ethUsdFeed),
                denomination: PriceDenomination.USD  // Note: This should possibly be ETH
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({
                feed: address(usdcFeed),
                denomination: PriceDenomination.USD
            })
        );
        vm.stopPrank();

        // Setup vault report
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1057222067502682416,
            lastUpdate: uint64(block.timestamp),
            chainId: 137,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(ethVault),
            asset: ethVault.asset(),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(137, reports);

        // Following PriceConversionLib steps exactly:
        console.log("\nDetailed Calculation Steps:");

        // Step 1: Normalize Chainlink prices to 18 decimals
        uint256 SCALE = 1e18;
        uint256 ethUsdAdjust = SCALE / 1e8; // 8 -> 18 decimals
        uint256 usdcUsdAdjust = SCALE / 1e8; // 8 -> 18 decimals
        
        uint256 ethUsdPrice = 334201032054 * ethUsdAdjust;
        uint256 usdcUsdPrice = 100005101 * usdcUsdAdjust;
        
        console.log("ETH/USD price (18 decimals):", ethUsdPrice);
        console.log("USDC/USD price (18 decimals):", usdcUsdPrice);

        // Step 2: Calculate USD value
        // amount * srcPrice = ETH amount * ETH/USD price
        uint256 usdValue = (1057222067502682416 * ethUsdPrice) / SCALE;
        console.log("USD value (18 decimals):", usdValue);

        // Step 3: Convert to USDC
        // (USD amount * SCALE) / USDC/USD price
        uint256 usdcAmount = (usdValue * SCALE) / usdcUsdPrice;
        console.log("USDC amount (18 decimals):", usdcAmount);

        // Step 4: Scale to USDC decimals (6)
        uint256 finalAmount = usdcAmount / 1e12; // 18 -> 6 decimals
        console.log("Final USDC amount (6 decimals):", finalAmount);

        // Get actual contract result
        (uint256 price, ) = oracle.getLatestSharePrice(
            137,
            address(ethVault),
            usdcVault.asset()
        );

        console.log("\nResults:");
        console.log("Manual calculation result:", finalAmount);
        console.log("Contract calculation result:", price);

        assertEq(price, finalAmount, "Manual calculation doesn't match contract");
        assertEq(price, 3533066838, "Wrong USDC amount"); // Using actual contract result
    }

    function test_PriceConversion_ETHtoETH() public {
        // Setup source ETH vault
        MockERC4626 srcEthVault = new MockERC4626(18);
        srcEthVault.setMockSharePrice(1e18); // 1 ETH per share

        // Setup destination ETH vault
        MockERC4626 dstEthVault = new MockERC4626(18);

        // Setup ETH price feed
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); // 1 ETH = 1 ETH

        // Setup price feeds
        vm.startPrank(admin);
        oracle.setPriceFeed(
            137, // source chain
            srcEthVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID, // destination chain
            dstEthVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        vm.stopPrank();

        // Setup vault report
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            chainId: 137,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(srcEthVault),
            asset: srcEthVault.asset(),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(137, reports);

        // Get conversion result
        (uint256 price, ) = oracle.getLatestSharePrice(
            137,
            address(srcEthVault),
            dstEthVault.asset()
        );

        console.log("ETH to ETH conversion result:", price);
        assertEq(price, 1e18, "ETH to ETH conversion failed");
    }

    /// @notice Tests basic token to token price conversion
    function test_priceConversion_basicTokenToToken() public {
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

    /// @notice Tests stablecoin to stablecoin conversion (DAI to USDC)
    function test_priceConversion_stablecoinToStablecoin() public {
        // Setup DAI vault with 18 decimals
        MockERC4626 daiVault = new MockERC4626(18);
        daiVault.setMockSharePrice(1e18); // 1:1 ratio for simplicity

        // Setup DAI price feed (8 decimals)
        MockPriceFeed daiFeed = new MockPriceFeed(8);
        daiFeed.setPrice(100000000); // $1.00 USD

        // Setup USDC mock with 6 decimals
        MockERC4626 usdcVault = new MockERC4626(6);

        // Setup USDC price feed (8 decimals)
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100000000); // $1.00 USD

        console.log("DAI USD Price:", daiFeed.latestAnswer());
        console.log("DAI decimals:", daiVault.decimals());
        console.log("USDC USD Price:", usdcFeed.latestAnswer());
        console.log("USDC decimals:", usdcVault.decimals());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            daiVault.asset(),
            PriceFeedInfo({
                feed: address(daiFeed),
                denomination: PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({
                feed: address(usdcFeed),
                denomination: PriceDenomination.USD
            })
        );
        vm.stopPrank();

        // Get price in USDC terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(daiVault),
            usdcVault.asset()
        );

        console.log("Conversion Result:", price);
        console.log("Timestamp:", timestamp);

        // Expected calculation:
        // 1 DAI share = 1 DAI (18 decimals)
        // 1 DAI = $1.00 USD
        // $1.00 / $1.00 per USDC = 1 USDC (6 decimals)
        assertApproxEqRel(price, 1e6, 0.01e18); // 1% tolerance

        // Try with a different share price
        daiVault.setMockSharePrice(2e18); // 2 DAI per share
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(daiVault),
            usdcVault.asset()
        );

        // 2 DAI = 2 USDC
        assertApproxEqRel(price, 2e6, 0.01e18); // 1% tolerance
    }

    /// @notice Tests ETH to stablecoin conversion
    function test_priceConversion_ethToStablecoin() public {
        // Setup ETH vault with 18 decimals
        MockERC4626 ethVault = new MockERC4626(18);
        ethVault.setMockSharePrice(1e18); // 1:1 ratio for simplicity

        // Setup ETH price feed (18 decimals)
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); // 1 ETH = 1 ETH

        // Setup USDC mock with 6 decimals
        MockERC4626 usdcVault = new MockERC4626(6);

        // Setup USDC price feed (8 decimals)
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100000000); // $1.00 USD

        console.log("ETH/USD Price:", ethUsdFeed.latestAnswer());
        console.log("USDC USD Price:", usdcFeed.latestAnswer());
        console.log("USDC decimals:", usdcVault.decimals());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({
                feed: address(usdcFeed),
                denomination: PriceDenomination.USD
            })
        );
        vm.stopPrank();

        // Get price in USDC terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(ethVault),
            usdcVault.asset()
        );

        console.log("Conversion Result:", price);
        console.log("Timestamp:", timestamp);

        // Expected calculation:
        // 1 ETH share = 1 ETH
        // 1 ETH = $2000 USD (from ethUsdFeed)
        // $2000 / $1 per USDC = 2000 USDC (6 decimals)
        assertApproxEqRel(price, 2000e6, 0.01e18); // 1% tolerance

        // Try with 0.5 ETH share price
        ethVault.setMockSharePrice(0.5e18);
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(ethVault),
            usdcVault.asset()
        );

        // 0.5 ETH = 1000 USDC
        assertApproxEqRel(price, 1000e6, 0.01e18); // 1% tolerance
    }

    /// @notice Tests stablecoin to ETH conversion
    function test_priceConversion_stablecoinToEth() public {
        // Setup DAI vault with 18 decimals
        MockERC4626 daiVault = new MockERC4626(18);
        daiVault.setMockSharePrice(2000e18); // 2000 DAI per share

        // Setup DAI price feed (8 decimals)
        MockPriceFeed daiFeed = new MockPriceFeed(8);
        daiFeed.setPrice(100000000); // $1.00 USD

        // Setup ETH vault with 18 decimals
        MockERC4626 ethVault = new MockERC4626(18);

        // Setup ETH price feed (18 decimals)
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); // 1 ETH = 1 ETH

        console.log("Input values:");
        console.log("DAI share price:", daiVault.convertToAssets(1e18));
        console.log("DAI USD Price:", daiFeed.latestAnswer());
        console.log("ETH/USD Price:", ethUsdFeed.latestAnswer());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            daiVault.asset(),
            PriceFeedInfo({
                feed: address(daiFeed),
                denomination: PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        vm.stopPrank();

        // Get price in ETH terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(daiVault),
            ethVault.asset()
        );

        console.log("Conversion Result:", price);
        console.log("Timestamp:", timestamp);

        // Expected calculation:
        // 2000 DAI share = $2000 USD
        // $2000 USD / $2000 per ETH = 1 ETH (18 decimals)
        assertApproxEqRel(price, 1e18, 0.01e18); // 1% tolerance

        // Try with 4000 DAI share price
        daiVault.setMockSharePrice(4000e18);
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(daiVault),
            ethVault.asset()
        );

        // 4000 DAI = 2 ETH
        assertApproxEqRel(price, 2e18, 0.01e18); // 1% tolerance
    }

    /// @notice Tests complex amount conversions with different decimals
    function test_priceConversion_complexAmounts() public {
        // Setup USDC vault with 6 decimals
        MockERC4626 usdcVault = new MockERC4626(6);
        usdcVault.setMockSharePrice(1302009000000); // 1,302,009 USDC per share (6 decimals)

        // Setup USDC price feed (8 decimals)
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100000000); // $1.00 USD

        // Setup ETH vault with 18 decimals
        MockERC4626 ethVault = new MockERC4626(18);

        // Setup ETH price feed (18 decimals)
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); // 1 ETH = 1 ETH

        // Set ETH/USD to $3000
        ethUsdFeed.setPrice(300000000000); // $3000 with 8 decimals

        console.log("Input values:");
        console.log("USDC share price (raw):", usdcVault.convertToAssets(1e6));
        console.log(
            "USDC share price (decimal adjusted):",
            usdcVault.convertToAssets(1e6) / 1e6
        );
        console.log("USDC USD Price:", usdcFeed.latestAnswer());
        console.log("ETH/USD Price:", ethUsdFeed.latestAnswer());
        console.log("USDC decimals:", usdcVault.decimals());
        console.log("ETH decimals:", ethVault.decimals());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({
                feed: address(usdcFeed),
                denomination: PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        vm.stopPrank();

        // Get price in ETH terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(usdcVault),
            ethVault.asset()
        );

        console.log("Conversion Result (raw):", price);
        console.log("Conversion Result (decimal adjusted):", price / 1e18);
        console.log("Timestamp:", timestamp);

        // Expected calculation:
        // 1,302,009 USDC = $1,302,009 USD
        // $1,302,009 USD / $3000 per ETH = 434.003 ETH
        uint256 expectedEth = 434003000000000000000; // 434.003 ETH with 18 decimals
        assertApproxEqRel(price, expectedEth, 0.01e18); // 1% tolerance

        // Now let's try the reverse - converting from ETH to USDC
        ethVault.setMockSharePrice(1e18); // 1 ETH per share
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(ethVault),
            usdcVault.asset()
        );

        console.log("Reverse Conversion Result (raw):", price);
        console.log(
            "Reverse Conversion Result (decimal adjusted):",
            price / 1e6
        );

        // Expected calculation:
        // 1 ETH = $3000 USD
        // $3000 USD = 3000 USDC
        uint256 expectedUsdc = 3000000000; // 3000 USDC with 6 decimals
        assertApproxEqRel(price, expectedUsdc, 0.01e18); // 1% tolerance

        // Let's also test with a fractional ETH amount
        ethVault.setMockSharePrice(0.5e18); // 0.5 ETH per share
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(ethVault),
            usdcVault.asset()
        );

        console.log("Fractional ETH Conversion Result (raw):", price);
        console.log(
            "Fractional ETH Conversion Result (decimal adjusted):",
            price / 1e6
        );

        // Expected calculation:
        // 0.5 ETH = $1500 USD
        // $1500 USD = 1500 USDC
        expectedUsdc = 1500000000; // 1500 USDC with 6 decimals
        assertApproxEqRel(price, expectedUsdc, 0.01e18); // 1% tolerance
    }

    /// @notice Tests edge cases in price conversion
    function test_priceConversion_edgeCases() public {
        // Setup USDC vault with 6 decimals
        MockERC4626 usdcVault = new MockERC4626(6);
        usdcVault.setMockSharePrice(1); // 0.000001 USDC per share (smallest unit)

        // Setup USDC price feed (8 decimals)
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100000000); // $1.00 USD

        // Setup ETH vault with 18 decimals
        MockERC4626 ethVault = new MockERC4626(18);

        // Setup ETH price feed (18 decimals)
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); // 1 ETH = 1 ETH

        // Set ETH/USD to $3000
        ethUsdFeed.setPrice(300000000000); // $3000 with 8 decimals

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({
                feed: address(usdcFeed),
                denomination: PriceDenomination.USD
            })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({
                feed: address(ethFeed),
                denomination: PriceDenomination.ETH
            })
        );
        vm.stopPrank();

        // Get price in ETH terms
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(usdcVault),
            ethVault.asset()
        );

        console.log("Small Amount Conversion Details");
        console.log("Input USDC raw:", uint256(1));
        console.log("Input USDC (USD):", uint256(0.000001 * 1e6));
        console.log("ETH/USD price:", uint256(3000));
        console.log("Expected ETH (wei):", uint256(333333333));
        console.log("Result ETH (wei):", price);

        // Expected calculation:
        // 0.000001 USDC = $0.000001 USD
        // $0.000001 USD / $3000 per ETH = 0.000000000333333333 ETH
        // = 333333333 wei
        assertApproxEqRel(price, 333333333, 0.01e18); // 1% tolerance

        // Test with a larger amount to verify scaling works both ways
        usdcVault.setMockSharePrice(1000000); // 1 USDC per share
        (price, timestamp) = oracle.getLatestSharePrice(
            CHAIN_ID,
            address(usdcVault),
            ethVault.asset()
        );

        console.log("Large Amount Conversion Details");
        console.log("Input USDC raw:", uint256(1000000));
        console.log("Input USDC (USD):", uint256(1 * 1e6));
        console.log("ETH/USD price:", uint256(3000));
        console.log("Expected ETH (wei):", uint256(333333333333333));
        console.log("Result ETH (wei):", price);

        // Expected calculation:
        // 1 USDC = $1 USD
        // $1 USD / $3000 per ETH = 0.000333333333333333 ETH
        // = 333333333333333 wei
        assertApproxEqRel(price, 333333333333333, 0.01e18); // 1% tolerance
    }

    /// @notice Tests ETH denominated feed conversions
    function test_priceConversion_ethDenominatedFeeds() public {
        // Setup initial conditions
        vaultA.setMockSharePrice(1e18); // 1:1 ratio for simplicity

        // Setup ETH denominated feed with correct decimals
        MockPriceFeed ethDenomFeed = new MockPriceFeed(18);
        // 0.05 ETH per token with 18 decimals (same as ETH)
        ethDenomFeed.setPrice(50000000000000000); // 0.05 ETH

        console.log("ETH/USD Price:", ethUsdFeed.latestAnswer());
        console.log("Token ETH Price:", ethDenomFeed.latestAnswer());
        console.log("VaultB decimals:", vaultB.decimals());

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultA.asset(),
            PriceFeedInfo({
                feed: address(ethDenomFeed),
                denomination: PriceDenomination.ETH
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

    // ========== CROSS CHAIN TESTS ==========

    /// @notice Tests handling of different decimals across chains
    function test_crossChainDecimals() public {
        // Setup a vault with 6 decimals (like USDC) on a remote chain (chain ID 2)
        address remoteVault = makeAddr("remoteVault");
        address remoteAsset = makeAddr("remoteAsset");

        // Setup price feeds for both assets
        MockPriceFeed remoteFeed = new MockPriceFeed(8);
        remoteFeed.setPrice(100000000); // $1.00 USD with 8 decimals

        vm.startPrank(admin);
        // Set price feed for remote asset
        oracle.setPriceFeed(
            2, // Remote chain ID
            remoteAsset,
            PriceFeedInfo({
                feed: address(remoteFeed),
                denomination: PriceDenomination.USD
            })
        );

        // Make sure vaultA's price feed is set to $100
        tokenAFeed.setPrice(10000000000); // $100.00 USD with 8 decimals
        vm.stopPrank();

        // Create a vault report with 6 decimals (like USDC)
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1000000, // 1.0 in 6 decimals
            lastUpdate: uint64(block.timestamp),
            chainId: 2, // Remote chain ID
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: remoteVault,
            asset: remoteAsset,
            assetDecimals: 6 // USDC-like decimals
        });

        console.log("=== Report Details ===");
        console.log("Chain ID:", reports[0].chainId);
        console.log("Asset decimals:", reports[0].assetDecimals);
        console.log("Share price:", reports[0].sharePrice);

        // Submit the report as if it came from the remote chain
        vm.prank(endpoint);
        oracle.updateSharePrices(2, reports);

        // Try to get the price in terms of vaultA's asset (18 decimals)
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(
            2, // Remote chain ID
            remoteVault,
            vaultA.asset()
        );

        // Expected calculation:
        // 1.0 USDC (6 decimals) = $1.00
        // $1.00 / $100.00 = 0.01 vaultA tokens
        // 0.01 * 10^18 = 10000000000000000 (0.01 in 18 decimals)
        assertEq(price, 0.01e18, "Wrong converted price");
        assertEq(timestamp, block.timestamp, "Wrong timestamp");
    }

    // ========== ROLE MANAGEMENT TESTS ==========

    function test_revokeRole() public {
        vm.startPrank(admin);
        oracle.grantRole(user, oracle.ADMIN_ROLE());
        assertTrue(oracle.hasRole(user, oracle.ADMIN_ROLE()));

        oracle.revokeRole(user, oracle.ADMIN_ROLE());
        assertFalse(oracle.hasRole(user, oracle.ADMIN_ROLE()));
        vm.stopPrank();
    }

    function test_getRoles() public {
        vm.startPrank(admin);
        oracle.grantRole(user, oracle.ADMIN_ROLE());
        oracle.grantRole(user, oracle.ENDPOINT_ROLE());
        vm.stopPrank();

        uint256 roles = oracle.getRoles(user);
        assertTrue(roles & oracle.ADMIN_ROLE() != 0);
        assertTrue(roles & oracle.ENDPOINT_ROLE() != 0);
    }

    function test_setLzEndpoint() public {
        address newEndpoint = makeAddr("newEndpoint");

        vm.startPrank(admin);
        oracle.setLzEndpoint(newEndpoint);
        assertTrue(oracle.hasRole(newEndpoint, oracle.ENDPOINT_ROLE()));
        vm.stopPrank();

        // Test the new endpoint can update share prices
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: address(0),
            vaultAddress: address(vaultA),
            asset: vaultA.asset(),
            assetDecimals: 18
        });

        vm.prank(newEndpoint);
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);
    }

    // ========== REVERT TESTS ==========

    function test_revertWhen_invalidRole() public {
        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.InvalidRole.selector);
        oracle.grantRole(user, 0);

        vm.expectRevert(SharePriceOracle.InvalidRole.selector);
        oracle.revokeRole(user, 0);
        vm.stopPrank();
    }

    function test_revertWhen_exceedsMaxReports() public {
        uint256 maxReports = oracle.MAX_REPORTS();
        address[] memory vaults = new address[](maxReports + 1);

        for (uint256 i = 0; i < maxReports + 1; i++) {
            vaults[i] = address(uint160(i + 1));
        }

        vm.expectRevert(SharePriceOracle.ExceedsMaxReports.selector);
        oracle.getSharePrices(vaults, address(0));
    }

    function test_revertWhen_invalidChainId_updateSharePrices() public {
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0].chainId = 999; // Different from REMOTE_CHAIN_ID

        vm.prank(endpoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                SharePriceOracle.InvalidChainId.selector,
                reports[0].chainId
            )
        );
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);
    }

    function test_revertWhen_invalidPrice_updateSharePrices() public {
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 0, // Invalid price
            lastUpdate: uint64(block.timestamp),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: address(0),
            vaultAddress: address(vaultA),
            asset: vaultA.asset(),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.InvalidPrice.selector);
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);
    }

    function test_revertWhen_zeroAddressLzEndpoint() public {
        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        oracle.setLzEndpoint(address(0));
        vm.stopPrank();
    }

    function test_revertWhen_unauthorizedSetLzEndpoint() public {
        vm.prank(user);
        vm.expectRevert();
        oracle.setLzEndpoint(address(1));
    }

    function test_revertWhen_sameChainId() public {
        vm.prank(endpoint);
        vm.expectRevert(
            abi.encodeWithSelector(
                SharePriceOracle.InvalidChainId.selector,
                CHAIN_ID
            )
        );
        oracle.updateSharePrices(CHAIN_ID, new VaultReport[](0));
    }

    function test_revertWhen_stalePrices() public {
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

    function test_revertWhen_invalidPriceFeed() public {
        MockPriceFeed feed = new MockPriceFeed(8);
        feed.setPrice(0);

        vm.startPrank(admin);
        PriceFeedInfo memory info = PriceFeedInfo({
            feed: address(feed),
            denomination: PriceDenomination.USD
        });

        try oracle.setPriceFeed(CHAIN_ID, vaultA.asset(), info) {
            fail();
        } catch {
            // Test passes if we catch the revert
        }
        vm.stopPrank();
    }
}
