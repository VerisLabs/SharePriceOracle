// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { SharePriceOracle } from "../../src/SharePriceOracle.sol";
import { MaxLzEndpoint } from "../../src/MaxLzEndpoint.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { MockPriceFeed } from "../mocks/MockPriceFeed.sol";
import { PriceFeedInfo, PriceDenomination, VaultReport } from "../../src/interfaces/ISharePriceOracle.sol";
import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";
import { VaultLib } from "../../src/libs/VaultLib.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";

/// @title SharePriceOracle Test Suite
/// @notice Comprehensive test suite for SharePriceOracle contract functionality
contract SharePriceOracleTest is Test {
    // ========== STATE VARIABLES ==========

    SharePriceOracle public oracle;
    MockPriceFeed public ethUsdFeed;
    MockPriceFeed public tokenAFeed;
    MockPriceFeed public tokenBFeed;
    MockPriceFeed public sequencer;
    MockERC4626 public vaultA;
    MockERC4626 public vaultB;
    address public admin;
    address public endpoint;
    address public user;
    uint32 public constant CHAIN_ID = 1;
    uint32 public constant REMOTE_CHAIN_ID = 2;

    // ========== EVENTS ==========

    event SharePriceUpdated(uint32 indexed srcChainId, address indexed vault, uint256 price, address rewardsDelegate);

    // ========== SETUP ==========

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        endpoint = makeAddr("endpoint");
        user = makeAddr("user");

        // Set chain ID to match CHAIN_ID constant
        vm.chainId(CHAIN_ID);

        // Deploy mock price feeds
        ethUsdFeed = new MockPriceFeed(8);
        tokenAFeed = new MockPriceFeed(8);
        tokenBFeed = new MockPriceFeed(8);
        sequencer = new MockPriceFeed(8);

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
        oracle = new SharePriceOracle(admin, address(ethUsdFeed));

        // Setup roles and price feeds
        oracle.grantRole(endpoint, oracle.ENDPOINT_ROLE());
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultA.asset(),
            PriceFeedInfo({ feed: address(tokenAFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultB.asset(),
            PriceFeedInfo({ feed: address(tokenBFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        vm.stopPrank();
    }

    // Add this helper function at the top of the contract
    function _setMockPrice(MockPriceFeed feed, uint256 price, uint256 timestamp) internal {
        feed.setPrice(int256(price));
        feed.setTimestamp(timestamp);
    }

    // ========== BASIC FUNCTIONALITY TESTS ==========

    function test_getSharePrices_singleVault() public {
        address[] memory vaults = new address[](1);
        vaults[0] = address(vaultA);

        address rewardsDelegate = makeAddr("delegate");
        VaultReport[] memory reports = oracle.getSharePrices(vaults, rewardsDelegate);

        assertEq(reports.length, 1, "Wrong number of reports");
        assertEq(reports[0].vaultAddress, address(vaultA), "Wrong vault address A");
        assertEq(reports[0].sharePrice, 1.5e18, "Wrong share price A");
        assertEq(reports[0].rewardsDelegate, rewardsDelegate, "Wrong rewards delegate A");
    }

    function test_getSharePrices_multipleVaults() public {
        address[] memory vaults = new address[](2);
        vaults[0] = address(vaultA);
        vaults[1] = address(vaultB);

        address rewardsDelegate = makeAddr("delegate");
        VaultReport[] memory reports = oracle.getSharePrices(vaults, rewardsDelegate);

        assertEq(reports.length, 2, "Wrong number of reports");
        assertEq(reports[0].vaultAddress, address(vaultA), "Wrong vault address A");
        assertEq(reports[1].vaultAddress, address(vaultB), "Wrong vault address B");
        assertEq(reports[0].sharePrice, 1.5e18, "Wrong share price A");
        assertEq(reports[1].sharePrice, 2e18, "Wrong share price B");
        assertEq(reports[0].rewardsDelegate, rewardsDelegate, "Wrong rewards delegate A");
        assertEq(reports[1].rewardsDelegate, rewardsDelegate, "Wrong rewards delegate B");
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
        emit SharePriceUpdated(REMOTE_CHAIN_ID, address(vaultA), 1.5e18, delegate);

        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);

        vm.stopPrank();
        vm.prank(admin);
        oracle.setPriceFeed(
            REMOTE_CHAIN_ID,
            reports[0].asset,
            PriceFeedInfo({ feed: address(tokenAFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(REMOTE_CHAIN_ID, address(vaultA), vaultB.asset());
        assertGt(price, 0, "Price should be non-zero");
        assertEq(timestamp, block.timestamp, "Wrong timestamp");
    }

    // ========== PRICE CONVERSION TESTS ==========
    function test_priceConversion_stablecoinToStablecoin_With_sequencer() public {
        uint256 baseTime = 1_000_000;
        uint256 sequencerStartTime = baseTime - 4000;

        vm.warp(baseTime);

        MockERC4626 daiVault = new MockERC4626(18);
        daiVault.setMockSharePrice(1e18); 


        MockPriceFeed daiFeed = new MockPriceFeed(8);
        daiFeed.setPrice(100_000_000); 
        daiFeed.setTimestamp(baseTime); 

        
        MockERC4626 usdcVault = new MockERC4626(6);

        
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100_000_000); 
        usdcFeed.setTimestamp(baseTime); 

        MockPriceFeed sequencerFeed = new MockPriceFeed(8);
        sequencerFeed.setSequencerStatus(false);
        sequencerFeed.setTimestamp(sequencerStartTime);

        vm.startPrank(admin);

        oracle.setSequencer(address(sequencerFeed));
        sequencerFeed.latestRoundData();

        oracle.setPriceFeed(
            CHAIN_ID,
            daiVault.asset(),
            PriceFeedInfo({ feed: address(daiFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );

        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );

        vm.stopPrank();

        (uint256 price,) = oracle.getLatestSharePrice(CHAIN_ID, address(daiVault), usdcVault.asset());

        assertApproxEqRel(price, 1e6, 0.01e18); 
    }

    function test_PriceConversion_ETHtoUSDC_RealWorldExample_banana() public {
        uint256 currentTime = block.timestamp;
        vm.warp(currentTime);

       
        MockERC4626 ethVault = new MockERC4626(18);
        ethVault.setMockSharePrice(1_057_222_067_502_682_416); 

      
        _setMockPrice(ethUsdFeed, 334_201_032_054, currentTime); 
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        _setMockPrice(usdcFeed, 100_005_101, currentTime); 
        MockERC4626 usdcVault = new MockERC4626(6);

        
        vm.startPrank(admin);
        oracle.setPriceFeed(
            137,
            ethVault.asset(),
            PriceFeedInfo({ feed: address(ethUsdFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        vm.stopPrank();

        
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1_057_222_067_502_682_416,
            lastUpdate: uint64(currentTime),
            chainId: 137,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(ethVault),
            asset: ethVault.asset(),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(137, reports);

        
        (uint256 price,) = oracle.getLatestSharePrice(137, address(ethVault), usdcVault.asset());

        assertEq(price, 3_533_066_838, "Wrong USDC amount");
    }

    function test_PriceConversion_ETHtoETH() public {

        uint256 currentTime = block.timestamp;
        vm.warp(currentTime);

       
        MockERC4626 srcEthVault = new MockERC4626(18);
        srcEthVault.setMockSharePrice(1e18); 

     
        MockERC4626 dstEthVault = new MockERC4626(18);

        
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        _setMockPrice(ethFeed, 1e18, currentTime); 

        
        vm.startPrank(admin);
        oracle.setPriceFeed(
            137,
            srcEthVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            dstEthVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        vm.stopPrank();

     
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e18,
            lastUpdate: uint64(currentTime),
            chainId: 137,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(srcEthVault),
            asset: srcEthVault.asset(),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(137, reports);

        MockPriceFeed(address(ethFeed)).latestRoundData();

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(137, address(srcEthVault), dstEthVault.asset());

        assertEq(price, 1e18, "ETH to ETH conversion failed");
        assertEq(timestamp, currentTime, "Wrong timestamp");
    }

   
    function test_priceConversion_basicTokenToToken() public {
        
        vaultA.setMockSharePrice(1e18); 
        tokenAFeed.setPrice(100e8); 
        tokenBFeed.setPrice(50e8); 

        address[] memory vaults = new address[](1);
        vaults[0] = address(vaultA);


        (uint256 priceInTokenB, uint64 timestamp) =
            oracle.getLatestSharePrice(CHAIN_ID, address(vaultA), vaultB.asset());

        assertEq(priceInTokenB, 2e18, "Wrong converted price");
        assertEq(timestamp, block.timestamp, "Wrong timestamp");
    }

   
    function test_priceConversion_stablecoinToStablecoin() public {
    
        MockERC4626 daiVault = new MockERC4626(18);
        daiVault.setMockSharePrice(1e18);


        MockPriceFeed daiFeed = new MockPriceFeed(8);
        daiFeed.setPrice(100_000_000); 

     
        MockERC4626 usdcVault = new MockERC4626(6);

      
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100_000_000); 

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            daiVault.asset(),
            PriceFeedInfo({ feed: address(daiFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        vm.stopPrank();

        
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(daiVault), usdcVault.asset());
        assertApproxEqRel(price, 1e6, 0.01e18); 

        daiVault.setMockSharePrice(2e18);
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(daiVault), usdcVault.asset());

        assertApproxEqRel(price, 2e6, 0.01e18); 
    }

    /// @notice Tests ETH to stablecoin conversion
    function test_priceConversion_ethToStablecoin() public {
       
        MockERC4626 ethVault = new MockERC4626(18);
        ethVault.setMockSharePrice(1e18); 

      
        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); 


        MockERC4626 usdcVault = new MockERC4626(6);

     
        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100_000_000);

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        vm.stopPrank();

       
        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(ethVault), usdcVault.asset());

        assertApproxEqRel(price, 2000e6, 0.01e18);

  
        ethVault.setMockSharePrice(0.5e18);
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(ethVault), usdcVault.asset());

  
        assertApproxEqRel(price, 1000e6, 0.01e18); 
    }

    /// @notice Tests stablecoin to ETH conversion
    function test_priceConversion_stablecoinToEth() public {
        MockERC4626 daiVault = new MockERC4626(18);
        daiVault.setMockSharePrice(2000e18); 

        MockPriceFeed daiFeed = new MockPriceFeed(8);
        daiFeed.setPrice(100_000_000); 

        MockERC4626 ethVault = new MockERC4626(18);

        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18);

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            daiVault.asset(),
            PriceFeedInfo({ feed: address(daiFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        vm.stopPrank();

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(daiVault), ethVault.asset());


        assertApproxEqRel(price, 1e18, 0.01e18); 

  
        daiVault.setMockSharePrice(4000e18);
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(daiVault), ethVault.asset());

        assertApproxEqRel(price, 2e18, 0.01e18); 
    }

    /// @notice Tests complex amount conversions with different decimals
    function test_priceConversion_complexAmounts() public {
        MockERC4626 usdcVault = new MockERC4626(6);
        usdcVault.setMockSharePrice(1_302_009_000_000); 

        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100_000_000); 

        MockERC4626 ethVault = new MockERC4626(18);

        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); 

        ethUsdFeed.setPrice(300_000_000_000); 

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        vm.stopPrank();

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(usdcVault), ethVault.asset());

        uint256 expectedEth = 434_003_000_000_000_000_000; 
        assertApproxEqRel(price, expectedEth, 0.01e18); 

        ethVault.setMockSharePrice(1e18); 
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(ethVault), usdcVault.asset());


        uint256 expectedUsdc = 3_000_000_000; 
        assertApproxEqRel(price, expectedUsdc, 0.01e18); 

        ethVault.setMockSharePrice(0.5e18); 
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(ethVault), usdcVault.asset());

        expectedUsdc = 1_500_000_000; 
        assertApproxEqRel(price, expectedUsdc, 0.01e18);
    }

    /// @notice Tests edge cases in price conversion
    function test_priceConversion_edgeCases() public {
        MockERC4626 usdcVault = new MockERC4626(6);
        usdcVault.setMockSharePrice(1); 

        MockPriceFeed usdcFeed = new MockPriceFeed(8);
        usdcFeed.setPrice(100_000_000); 

        MockERC4626 ethVault = new MockERC4626(18);

        MockPriceFeed ethFeed = new MockPriceFeed(18);
        ethFeed.setPrice(1e18); 

        ethUsdFeed.setPrice(300_000_000_000); 

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            usdcVault.asset(),
            PriceFeedInfo({ feed: address(usdcFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        oracle.setPriceFeed(
            CHAIN_ID,
            ethVault.asset(),
            PriceFeedInfo({ feed: address(ethFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        vm.stopPrank();

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(usdcVault), ethVault.asset());

        assertApproxEqRel(price, 333_333_333, 0.01e18); 

        usdcVault.setMockSharePrice(1_000_000);
        (price, timestamp) = oracle.getLatestSharePrice(CHAIN_ID, address(usdcVault), ethVault.asset());

        assertApproxEqRel(price, 333_333_333_333_333, 0.01e18); 
    }

    /// @notice Tests ETH denominated feed conversions
    function test_priceConversion_ethDenominatedFeeds() public {
        vaultA.setMockSharePrice(1e18); 

        MockPriceFeed ethDenomFeed = new MockPriceFeed(18);
        ethDenomFeed.setPrice(50_000_000_000_000_000);

        vm.startPrank(admin);
        oracle.setPriceFeed(
            CHAIN_ID,
            vaultA.asset(),
            PriceFeedInfo({ feed: address(ethDenomFeed), denomination: PriceDenomination.ETH, heartbeat: 1 hours })
        );
        vm.stopPrank();

        (uint256 price,) = oracle.getLatestSharePrice(CHAIN_ID, address(vaultA), vaultB.asset());
        assertApproxEqRel(price, 2e18, 0.01e18);
    }

    // ========== CROSS CHAIN TESTS ==========

    /// @notice Tests handling of different decimals across chains
    function test_crossChainDecimals() public {
        uint256 currentTime = block.timestamp;
        vm.warp(currentTime);

        address remoteVault = makeAddr("remoteVault");
        address remoteAsset = makeAddr("remoteAsset");

        MockPriceFeed remoteFeed = new MockPriceFeed(8);
        _setMockPrice(remoteFeed, 100_000_000, currentTime); 
        _setMockPrice(tokenAFeed, 10_000_000_000, currentTime); 

        vm.startPrank(admin);
        oracle.setPriceFeed(
            REMOTE_CHAIN_ID,
            remoteAsset,
            PriceFeedInfo({ feed: address(remoteFeed), denomination: PriceDenomination.USD, heartbeat: 1 hours })
        );
        vm.stopPrank();

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1_000_000,
            lastUpdate: uint64(currentTime),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: remoteVault,
            asset: remoteAsset,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);

        (uint256 price, uint64 timestamp) = oracle.getLatestSharePrice(REMOTE_CHAIN_ID, remoteVault, vaultA.asset());

        assertEq(price, 0.01e18, "Wrong converted price");
        assertEq(timestamp, currentTime, "Wrong timestamp");
    }

    // ========== ROLE MANAGEMENT TESTS ==========
    function test_setSequencer() public {
        assertEq(oracle.sequencer(), address(0), "Wrong sequencer");
        address newSequencer = makeAddr("newSequencer");
        vm.startPrank(admin);
        oracle.setSequencer(newSequencer);
        assertEq(oracle.sequencer(), newSequencer, "Wrong sequencer");
        vm.stopPrank();
    }

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
        reports[0].chainId = 999; 

        vm.prank(endpoint);
        vm.expectRevert(abi.encodeWithSelector(SharePriceOracle.InvalidChainId.selector, reports[0].chainId));
        oracle.updateSharePrices(REMOTE_CHAIN_ID, reports);
    }

    function test_revertWhen_invalidPrice_updateSharePrices() public {
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 0, 
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
        vm.expectRevert(abi.encodeWithSelector(SharePriceOracle.InvalidChainId.selector, CHAIN_ID));
        oracle.updateSharePrices(CHAIN_ID, new VaultReport[](0));
    }

    function test_revertWhen_stalePrices() public {
        vm.warp(block.timestamp + oracle.SHARE_PRICE_STALENESS_TOLERANCE() + 1);

        VaultReport memory report = VaultReport({
            sharePrice: 1.5e18,
            lastUpdate: uint64(block.timestamp - oracle.SHARE_PRICE_STALENESS_TOLERANCE() - 1),
            chainId: REMOTE_CHAIN_ID,
            rewardsDelegate: makeAddr("delegate"),
            vaultAddress: address(vaultA),
            asset: vaultA.asset(),
            assetDecimals: 18
        });

        (uint256 price,) = oracle.getLatestSharePrice(REMOTE_CHAIN_ID, report.vaultAddress, vaultB.asset());
        assertEq(price, 0, "Price should be zero due to staleness");
    }

    function test_revertWhen_invalidPriceFeed() public {
        MockPriceFeed feed = new MockPriceFeed(8);
        feed.setPrice(0);

        vm.startPrank(admin);
        PriceFeedInfo memory info =
            PriceFeedInfo({ feed: address(feed), denomination: PriceDenomination.USD, heartbeat: 1 hours });

        try oracle.setPriceFeed(CHAIN_ID, vaultA.asset(), info) {
            fail();
        } catch {
            // Test passes if we catch the revert
        }
        vm.stopPrank();
    }

    function test_revertWhen_sequencerIsFalse() public {
        MockPriceFeed feed = new MockPriceFeed(8);

        vm.startPrank(admin);
        sequencer.setPrice(1);
        oracle.setSequencer(address(sequencer));
        vm.stopPrank();

        vm.startPrank(admin);
        PriceFeedInfo memory info =
            PriceFeedInfo({ feed: address(feed), denomination: PriceDenomination.USD, heartbeat: 1 hours });

        try oracle.setPriceFeed(CHAIN_ID, vaultA.asset(), info) {
            fail();
        } catch {
            // Test passes if we catch the revert
        }
        vm.stopPrank();
    }
}
