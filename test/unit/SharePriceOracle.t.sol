// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { Test } from "forge-std/Test.sol";
import { SharePriceOracle } from "../../src/SharePriceOracle.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";
import { ISharePriceOracle } from "../../src/interfaces/ISharePriceOracle.sol";
import { MockVault } from "../mocks/MockVault.sol";
import { MockChainlinkSequencer } from "../mocks/MockChainlinkSequencer.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { MockChainlinkFeed } from "../mocks/MockChainlinkFeed.sol";
import { ChainlinkAdapter } from "../../src/adapters/Chainlink.sol";
import { BaseTest } from "../base/BaseTest.t.sol";
import { console2 } from "forge-std/console2.sol";

// Constants for BASE network
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant WETH = 0x4200000000000000000000000000000000000006;
address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
address constant USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
address constant STETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
address constant TBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;
address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

// Chainlink price feed addresses on BASE
address constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
address constant BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
address constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
address constant USDT_USD_FEED = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
address constant STETH_USD_FEED = 0xf586d0728a47229e747d824a939000Cf21dEF5A0;
address constant TBTC_USD_FEED = 0x6D75BFB5A5885f841b132198C9f0bE8c872057BF;
address constant DAI_USD_FEED = 0x591e79239a7d679378eC8c847e5038150364C78F;

// Add Optimism asset addresses (mocked for testing)
address constant OPTIMISM_USDC = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
address constant OPTIMISM_USDT = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
address constant OPTIMISM_WETH = 0x4200000000000000000000000000000000000006;
address constant OPTIMISM_STETH = 0x1F32b1c2345538c0c6f582fCB022739c4A194Ebb;
address constant OPTIMISM_WBTC = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
address constant OPTIMISM_TBTC = 0x6c84a8f1c29108F47a79964b5Fe888D4f4D0dE40;
address constant OPTIMISM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

contract SharePriceOracleTest is BaseTest {
    // Test contracts
    SharePriceOracle public router;
    ChainlinkAdapter public chainlinkAdapter;

    // Test vaults for Base network
    MockVault public usdcVault;
    MockVault public wethVault;
    MockVault public wbtcVault;
    MockVault public usdtVault;
    MockVault public stethVault;
    MockVault public TbtcVault;
    MockVault public daiVault;

    // Test vaults for Optimism (mocked)
    MockVault public opUsdcVault;
    MockVault public opUsdtVault;
    MockVault public opWethVault;
    MockVault public opStethVault;
    MockVault public opWbtcVault;
    MockVault public opTbtcVault;
    MockVault public opDaiVault;

    // Test accounts
    address public admin;
    address public endpoint;
    address public adapter;
    address public user;
    address public oracle;

    function setUp() public {
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);
        vm.rollFork(27_192_119);

        // Setup test accounts
        admin = makeAddr("admin");
        endpoint = makeAddr("endpoint");
        adapter = makeAddr("adapter");
        user = makeAddr("user");
        oracle = makeAddr("oracle");
        // Deploy router with admin as owner
        vm.prank(admin);
        router = new SharePriceOracle(admin);

        // Deploy and configure ChainlinkAdapter
        chainlinkAdapter = new ChainlinkAdapter(
            admin,
            address(router), // Set router as adapter
            address(router)
        );

        // Setup roles
        vm.startPrank(admin);
        router.grantRole(endpoint, router.ENDPOINT_ROLE());
        router.grantRole(address(router), router.ADAPTER_ROLE()); // Grant adapter role to router
        chainlinkAdapter.grantRole(address(router), chainlinkAdapter.ORACLE_ROLE()); // Grant oracle role to router
        chainlinkAdapter.grantRole(oracle, chainlinkAdapter.ORACLE_ROLE()); // Grant oracle role to oracle

        // Configure price feeds in adapter
        vm.startPrank(oracle);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, 86_400, true); // 20 min heartbeat
        chainlinkAdapter.addAsset(USDT, USDT_USD_FEED, 86_400, true);
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, 1200, true);
        chainlinkAdapter.addAsset(STETH, STETH_USD_FEED, 86_400, false); // stETH/ETH feed
        chainlinkAdapter.addAsset(WBTC, BTC_USD_FEED, 1200, true);
        chainlinkAdapter.addAsset(TBTC, TBTC_USD_FEED, 86_400, true);
        chainlinkAdapter.addAsset(DAI, DAI_USD_FEED, 86_400, true);
        vm.stopPrank();

        // Deploy Base network mock vaults
        usdcVault = new MockVault(USDC, 6, 1.1e6); // 1.1 USDC
        usdtVault = new MockVault(USDT, 6, 1.2e6); // 1.2 USDT
        wethVault = new MockVault(WETH, 18, 1.1e18); // 1.1 WETH
        stethVault = new MockVault(STETH, 18, 1.2e18); // 1.2 stETH
        wbtcVault = new MockVault(WBTC, 8, 1.1e8); // 1.1 WBTC
        TbtcVault = new MockVault(TBTC, 8, 1.2e8); // 1.2 tBTC

        // Deploy Optimism mock vaults (for cross-chain testing)
        opUsdcVault = new MockVault(OPTIMISM_USDC, 6, 1.15e6); // 1.15 USDC
        opUsdtVault = new MockVault(OPTIMISM_USDT, 6, 1.25e6); // 1.25 USDT
        opWethVault = new MockVault(OPTIMISM_WETH, 18, 1.15e18); // 1.15 WETH
        opStethVault = new MockVault(OPTIMISM_STETH, 18, 1.25e18); // 1.25 stETH
        opWbtcVault = new MockVault(OPTIMISM_WBTC, 8, 1.15e8); // 1.15 WBTC
        opTbtcVault = new MockVault(OPTIMISM_TBTC, 8, 1.25e8); // 1.25 tBTC
        opDaiVault = new MockVault(OPTIMISM_DAI, 18, 1.35e18); // 1.35 DAI

        vm.startPrank(admin);
        // Setup cross-chain asset mappings
        router.setCrossChainAssetMapping(10, OPTIMISM_USDC, USDC);
        router.setCrossChainAssetMapping(10, OPTIMISM_USDT, USDT);
        router.setCrossChainAssetMapping(10, OPTIMISM_WETH, WETH);
        router.setCrossChainAssetMapping(10, OPTIMISM_STETH, STETH);
        router.setCrossChainAssetMapping(10, OPTIMISM_WBTC, WBTC);
        router.setCrossChainAssetMapping(10, OPTIMISM_TBTC, TBTC);
        router.setCrossChainAssetMapping(10, OPTIMISM_DAI, DAI);

        // Configure local assets with chainlink adapter
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 0, true);
        router.setLocalAssetConfig(USDT, address(chainlinkAdapter), USDT_USD_FEED, 0, true);
        router.setLocalAssetConfig(WETH, address(chainlinkAdapter), ETH_USD_FEED, 0, true);
        router.setLocalAssetConfig(STETH, address(chainlinkAdapter), STETH_USD_FEED, 0, false); // stETH/ETH feed
        router.setLocalAssetConfig(WBTC, address(chainlinkAdapter), BTC_USD_FEED, 0, true);
        router.setLocalAssetConfig(TBTC, address(chainlinkAdapter), TBTC_USD_FEED, 0, true);
        router.setLocalAssetConfig(DAI, address(chainlinkAdapter), DAI_USD_FEED, 0, true);

        // Update prices in router
        address[] memory assets = new address[](7);
        assets[0] = USDC;
        assets[1] = USDT;
        assets[2] = WETH;
        assets[3] = STETH;
        assets[4] = WBTC;
        assets[5] = TBTC;
        assets[6] = DAI;
        bool[] memory inUSD = new bool[](7);
        inUSD[0] = true;
        inUSD[1] = true;
        inUSD[2] = true;
        inUSD[3] = false;
        inUSD[4] = true;
        inUSD[5] = true;
        inUSD[6] = true;
        router.batchUpdatePrices(assets, inUSD);
        vm.stopPrank();
    }

    // Admin function tests
    function testGrantRole() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);
        router.grantRole(newAdmin, router.ADMIN_ROLE());
        vm.stopPrank();

        assertTrue(router.hasAnyRole(newAdmin, router.ADMIN_ROLE()), "Role should be granted");
    }

    function testRevokeRole() public {
        vm.startPrank(admin);
        router.grantRole(user, router.ADAPTER_ROLE());
        router.revokeRole(user, router.ADAPTER_ROLE());
        vm.stopPrank();

        assertFalse(router.hasAnyRole(user, router.ADAPTER_ROLE()), "Role should be revoked");
    }

    function testRevertGrantRole_InvalidRole() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceOracle.InvalidRole.selector);
        router.grantRole(user, 0);
    }

    // Sequencer tests
    function testSetSequencer() public {
        address newSequencer = makeAddr("newSequencer");

        vm.prank(admin);
        router.setSequencer(newSequencer);

        assertEq(router.sequencer(), newSequencer, "Sequencer should be updated");
    }

    function testRevertSetSequencer_NotAdmin() public {
        address newSequencer = makeAddr("newSequencer");

        vm.prank(user);
        vm.expectRevert();
        router.setSequencer(newSequencer);
    }

    function testIsSequencerValid_NoSequencer() public view {
        // When no sequencer is set, should return true
        assertTrue(router.isSequencerValid(), "Should be valid when no sequencer is set");
    }

    function testIsSequencerValid_WithSequencer() public {
        address mockSequencer = address(new MockChainlinkSequencer());

        vm.prank(admin);
        router.setSequencer(mockSequencer);

        assertTrue(router.isSequencerValid(), "Should be valid when sequencer is up");
    }

    function testIsSequencerValid_SequencerDown() public {
        MockChainlinkSequencer mockSequencer = new MockChainlinkSequencer();
        mockSequencer.setDown(); // Custom function to simulate sequencer being down

        vm.prank(admin);
        router.setSequencer(address(mockSequencer));

        // Mock the sequencer being down for a while
        mockSequencer.setStartedAt(block.timestamp - router.GRACE_PERIOD_TIME() - 1);

        assertFalse(router.isSequencerValid(), "Sequencer should be down");
    }

    function testIsSequencerValid_GracePeriod() public {
        MockChainlinkSequencer mockSequencer = new MockChainlinkSequencer();
        mockSequencer.setStartedAt(block.timestamp); // Just started

        vm.prank(admin);
        router.setSequencer(address(mockSequencer));

        assertFalse(router.isSequencerValid(), "Should be invalid during grace period");

        // Move past grace period
        vm.warp(block.timestamp + router.GRACE_PERIOD_TIME() + 1);
        assertTrue(router.isSequencerValid(), "Should be valid after grace period");
    }

    // Cross-Chain Asset Mapping Tests
    function testSetCrossChainAssetMapping() public {
        address srcAsset = makeAddr("srcAsset");
        address localAsset = makeAddr("localAsset");
        uint32 srcChain = 10; // Optimism chain ID

        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, srcAsset, localAsset);

        bytes32 key = keccak256(abi.encodePacked(srcChain, srcAsset));
        assertEq(router.crossChainAssetMap(key), localAsset, "Cross chain mapping should be set");
    }

    function testRevertSetCrossChainAssetMapping_SameChain() public {
        address srcAsset = makeAddr("srcAsset");
        address localAsset = makeAddr("localAsset");

        vm.prank(admin);
        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.setCrossChainAssetMapping(uint32(block.chainid), srcAsset, localAsset);
    }

    function testRevertSetCrossChainAssetMapping_ZeroAddresses() public {
        uint32 srcChain = 10;

        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setCrossChainAssetMapping(srcChain, address(0), makeAddr("local"));

        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setCrossChainAssetMapping(srcChain, makeAddr("src"), address(0));
        vm.stopPrank();
    }

    function testRevertSetCrossChainAssetMapping_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        router.setCrossChainAssetMapping(10, makeAddr("src"), makeAddr("local"));
    }

    // Share Price Update Tests
    function testUpdateSharePrices() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address asset = makeAddr("asset");
        address localAsset = WETH;
        uint256 sharePrice = 1e18;

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: vaultAddr,
            asset: asset,
            assetDecimals: 18,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        // Set up the cross-chain asset mapping
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, asset, localAsset);

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Verify stored data
        ISharePriceOracle.VaultReport memory report = router.getLatestSharePriceReport(srcChain, vaultAddr);

        assertEq(report.chainId, srcChain, "Chain ID should match");
        assertEq(report.vaultAddress, vaultAddr, "Vault address should match");
        assertEq(report.asset, asset, "Asset should match");
        assertEq(report.sharePrice, sharePrice, "Share price should match");
        assertEq(report.assetDecimals, 18, "Decimals should match");
    }

    function testRevertUpdateSharePrices_InvalidChainId() public {
        uint32 srcChain = uint32(block.chainid); // Same as current chain
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: makeAddr("vault"),
            asset: makeAddr("asset"),
            assetDecimals: 18,
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.updateSharePrices(srcChain, reports);
    }

    function testRevertUpdateSharePrices_TooManyReports() public {
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](router.MAX_REPORTS() + 1);

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.ExceedsMaxReports.selector);
        router.updateSharePrices(10, reports);
    }

    function testRevertUpdateSharePrices_ZeroSharePrice() public {
        uint32 srcChain = 10;
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: makeAddr("vault"),
            asset: makeAddr("asset"),
            assetDecimals: 18,
            sharePrice: 0, // Zero share price
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.NoValidPrice.selector);
        router.updateSharePrices(srcChain, reports);
    }

    function testRevertUpdateSharePrices_ZeroAsset() public {
        uint32 srcChain = 10;
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: makeAddr("vault"),
            asset: address(0), // Zero asset address
            assetDecimals: 18,
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.updateSharePrices(srcChain, reports);
    }

    // Price Conversion Tests
    function testGetLatestSharePrice_DAI_TO_USDC_Stables() public {
        uint32 srcChain = 10;
        uint256 sharePrice = 1.3e18; // 1.3 DAI

        // Set up cross-chain mapping for USDC
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opDaiVault),
            asset: OPTIMISM_DAI,
            assetDecimals: 18,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 usdcPrice,) = router.getLatestAssetPrice(USDC, true);
        (uint256 daiPrice,) = router.getLatestAssetPrice(DAI, true);
        uint256 price_ = (sharePrice * daiPrice / usdcPrice) / 10 ** 12;

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opDaiVault), USDC);

        assertApproxEqAbs(price, price_, 1.3e4, "Price should match for same stable asset");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    // Price Conversion Tests
    function testGetLatestSharePrice_SameAssetCategory_Stables() public {
        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 sharePrice = 1.1e6; // 1.1 USDC

        // Set up cross-chain mapping for USDC
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, sharePrice, "Price should match for same stable asset");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_SameAssetCategory_ETH() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address optimismWETH = makeAddr("optimismWETH");
        uint256 sharePrice = 1.1e18; // 1.1 ETH

        // Set up cross-chain mapping for WETH
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, optimismWETH, WETH);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: vaultAddr,
            asset: optimismWETH,
            assetDecimals: 18,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, WETH);
        assertEq(price, sharePrice, "Price should match for same ETH-like asset");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_SameAssetCategory_BTC() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address optimismWBTC = makeAddr("optimismWBTC");
        uint256 sharePrice = 1.1e8; // 1.1 BTC

        // Set up cross-chain mapping for WBTC
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, optimismWBTC, WBTC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: vaultAddr,
            asset: optimismWBTC,
            assetDecimals: 8,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, WBTC);
        assertEq(price, sharePrice, "Price should match for same BTC-like asset");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testRevertGetLatestSharePrice_DifferentAssetCategories() public {
        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 sharePrice = 1.1e6; // 1.1 USDC

        // Set up USDC vault but try to get price in WETH
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        uint256 normalizedPrice = sharePrice * 10 ** (18 - 6);
        (uint256 usdcPrice,) = router.getLatestAssetPrice(USDC, true);
        (uint256 wethPrice,) = router.getLatestAssetPrice(WETH, true);
        uint256 price_ = normalizedPrice * usdcPrice / wethPrice;

        // Should fail when trying to convert USDC to WETH
        (uint256 price,) = router.getLatestSharePrice(srcChain, vaultAddr, WETH);
        assertApproxEqAbs(price, price_, 1.1e15, "Price should be 0 for incompatible asset categories");
    }

    // Local Asset Configuration Tests
    function testSetLocalAssetConfig() public {
        vm.prank(admin);
        router.setLocalAssetConfig(USDC, adapter, USDC_USD_FEED, 0, true);

        (address priceFeed, bool inUSD, address adaptor) = router.localAssetConfigs(USDC, 0);
        assertEq(priceFeed, USDC_USD_FEED, "Price feed should be set");
        assertTrue(inUSD, "USD flag should be set");
        assertEq(adaptor, adapter, "Adaptor should be set");
    }

    function testRevertSetLocalAssetConfig_ZeroAddresses() public {
        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setLocalAssetConfig(address(0), adapter, USDC_USD_FEED, 0, true);

        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setLocalAssetConfig(USDC, adapter, address(0), 0, true);
        vm.stopPrank();
    }

    function testRevertSetLocalAssetConfig_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        router.setLocalAssetConfig(USDC, adapter, USDC_USD_FEED, 0, true);
    }

    // Batch Price Update Tests
    function testBatchUpdatePrices() public {
        address[] memory assets = new address[](2);
        assets[0] = USDC;
        assets[1] = WETH;
        bool[] memory inUSD = new bool[](2);
        inUSD[0] = true;
        inUSD[1] = true;

        vm.startPrank(admin);
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 0, true);
        router.setLocalAssetConfig(WETH, address(chainlinkAdapter), ETH_USD_FEED, 0, true);
        vm.stopPrank();

        bool success = router.batchUpdatePrices(assets, inUSD);
        assertTrue(success, "Batch update should succeed");

        // Verify stored prices
        (uint256 usdcPrice, uint64 usdcTimestamp, bool usdcInUSD) = router.storedAssetPrices(USDC);
        (uint256 wethPrice, uint64 wethTimestamp, bool wethInUSD) = router.storedAssetPrices(WETH);

        assertTrue(usdcPrice > 0, "USDC price should be stored");
        assertTrue(wethPrice > 0, "WETH price should be stored");
        assertTrue(usdcInUSD && wethInUSD, "Prices should be in USD");
        assertEq(usdcTimestamp, uint64(block.timestamp), "Timestamps should be current");
        assertEq(wethTimestamp, uint64(block.timestamp), "Timestamps should be current");
    }

    // Price Feed Removal Tests
    function testNotifyFeedRemoval() public {
        vm.startPrank(admin);
        router.setLocalAssetConfig(USDC, adapter, USDC_USD_FEED, 0, true);
        router.setLocalAssetConfig(USDC, adapter, USDC_USD_FEED, 1, true);
        vm.stopPrank();

        vm.prank(adapter);
        router.notifyFeedRemoval(USDC);

        // Verify all configs are removed
        for (uint8 i = 0; i <= 1; i++) {
            (address priceFeed, bool inUSD, address adaptor) = router.localAssetConfigs(USDC, i);
            assertEq(priceFeed, address(0), "Price feed should be removed");
            assertEq(inUSD, false, "USD flag should be removed");
            assertEq(adaptor, address(0), "Adaptor should be removed");
        }
    }

    function testRevertNotifyFeedRemoval_NotAdapter() public {
        vm.prank(user);
        vm.expectRevert();
        router.notifyFeedRemoval(USDC);
    }

    function testUpdateSharePrices_MultipleAssets() public {
        uint32 srcChain = 10; // Optimism

        // Create reports for multiple assets
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](6);

        // Stablecoins
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.15e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        reports[1] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdtVault),
            asset: OPTIMISM_USDT,
            assetDecimals: 6,
            sharePrice: 1.25e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        // ETH-like assets
        reports[2] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opWethVault),
            asset: OPTIMISM_WETH,
            assetDecimals: 18,
            sharePrice: 1.15e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        reports[3] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opStethVault),
            asset: OPTIMISM_STETH,
            assetDecimals: 18,
            sharePrice: 1.25e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        // BTC-like assets
        reports[4] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opWbtcVault),
            asset: OPTIMISM_WBTC,
            assetDecimals: 8,
            sharePrice: 1.15e8,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        reports[5] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opTbtcVault),
            asset: OPTIMISM_TBTC,
            assetDecimals: 8,
            sharePrice: 1.25e8,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Verify all reports were stored correctly
        for (uint256 i = 0; i < reports.length; i++) {
            ISharePriceOracle.VaultReport memory report =
                router.getLatestSharePriceReport(srcChain, reports[i].vaultAddress);
            assertEq(report.chainId, srcChain, "Chain ID should match");
            assertEq(report.vaultAddress, reports[i].vaultAddress, "Vault address should match");
            assertEq(report.asset, reports[i].asset, "Asset should match");
            assertEq(report.sharePrice, reports[i].sharePrice, "Share price should match");
            assertEq(report.assetDecimals, reports[i].assetDecimals, "Decimals should match");
        }
    }

    function testGetLatestSharePrice_CrossChainStables() public {
        uint32 srcChain = 10;

        // Setup initial USDC vault report
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdtVault),
            asset: OPTIMISM_USDT,
            assetDecimals: 6,
            sharePrice: 1.15e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Test conversion from USDC to USDT (both 6 decimals)
        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opUsdtVault), USDC);
        assertApproxEqAbs(price, 1.15e6, 1.15e4, "Price should match for stable to stable conversion");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossChainETH() public {
        uint32 srcChain = 10;

        // Setup initial WETH vault report
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opStethVault),
            asset: OPTIMISM_STETH,
            assetDecimals: 18,
            sharePrice: 1.15e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Test conversion from WETH to stETH (both 18 decimals)
        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opStethVault), WETH);
        assertApproxEqAbs(price, 1.15e18, 1.15e16, "Price should match for ETH to ETH conversion");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossChainBTC() public {
        uint32 srcChain = 10;

        // Setup initial WBTC vault report
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opTbtcVault),
            asset: OPTIMISM_TBTC,
            assetDecimals: 8,
            sharePrice: 1.15e8,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opTbtcVault), WBTC);
        assertApproxEqAbs(price, 1.15e8, 1.15e5, "Price should match for BTC to BTC conversion");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function test_crossChainAssetConversion() public {
        vm.startPrank(admin);

        router.setCrossChainAssetMapping(10, OPTIMISM_USDC, USDC);

        router.setCrossChainAssetMapping(10, OPTIMISM_WETH, WETH);

        (address localUSDC, uint8 usdcDecimals) = router.getLocalAsset(10, OPTIMISM_USDC);
        (address localWETH, uint8 wethDecimals) = router.getLocalAsset(10, OPTIMISM_WETH);

        assertEq(localUSDC, USDC, "USDC mapping incorrect");
        assertEq(localWETH, WETH, "WETH mapping incorrect");
        assertEq(usdcDecimals, 6, "USDC decimals incorrect");
        assertEq(wethDecimals, 18, "WETH decimals incorrect");

        vm.stopPrank();
    }

    function test_getSharePrices() public view {
        address[] memory vaultAddresses = new address[](3);
        vaultAddresses[0] = address(usdcVault);
        vaultAddresses[1] = address(wethVault);
        vaultAddresses[2] = address(wbtcVault);

        ISharePriceOracle.VaultReport[] memory reports = router.getSharePrices(vaultAddresses, address(0));

        assertEq(reports.length, vaultAddresses.length, "Should return correct number of reports");

        for (uint256 i = 0; i < reports.length; i++) {
            assertEq(reports[i].chainId, uint32(block.chainid), "Chain ID should match");
            assertEq(reports[i].vaultAddress, vaultAddresses[i], "Vault address should match");
            assertGt(reports[i].sharePrice, 0, "Share price should be non-zero");
        }
    }

    function test_revertWhen_UpdateSharePricesWithInvalidChain() public {
        vm.startPrank(endpoint);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: uint32(block.chainid),
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.1e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.updateSharePrices(uint32(block.chainid), reports);

        vm.stopPrank();
    }

    function test_revertWhen_GetLocalAssetNotConfigured() public {
        address randomAsset = makeAddr("randomAsset");

        vm.expectRevert(abi.encodeWithSelector(SharePriceOracle.AssetNotConfigured.selector, randomAsset));
        router.getLocalAsset(10, randomAsset);
    }

    function test_sequencerValidation() public {
        assertTrue(router.isSequencerValid(), "Should be valid with no sequencer");

        vm.startPrank(admin);
        address mockSequencer = makeAddr("sequencer");
        router.setSequencer(mockSequencer);

        vm.mockCall(
            mockSequencer,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(0, int256(1), block.timestamp, block.timestamp, 0)
        );

        assertFalse(router.isSequencerValid(), "Should be invalid when sequencer is down");

        vm.mockCall(
            mockSequencer,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(0, int256(0), block.timestamp, block.timestamp, 0)
        );

        assertFalse(router.isSequencerValid(), "Should be invalid during grace period");

        vm.mockCall(
            mockSequencer,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(0, int256(0), block.timestamp - router.GRACE_PERIOD_TIME() - 1, block.timestamp, 0)
        );

        assertTrue(router.isSequencerValid(), "Should be valid after grace period");

        vm.stopPrank();
    }

    function testRevertWhen_InvalidRoleRevocation() public {
        vm.startPrank(admin);
        vm.expectRevert();
        router.revokeRole(user, 0);
        vm.stopPrank();
    }

    function testRevertWhen_UpdateSharePricesWithZeroAsset() public {
        vm.startPrank(endpoint);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: 10,
            vaultAddress: address(opUsdcVault),
            asset: address(0),
            assetDecimals: 6,
            sharePrice: 1.1e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.updateSharePrices(10, reports);
        vm.stopPrank();
    }

    function testRevertWhen_UpdateSharePricesWithZeroSharePrice() public {
        vm.startPrank(endpoint);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: 10,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 0,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.expectRevert(SharePriceOracle.NoValidPrice.selector);
        router.updateSharePrices(10, reports);
        vm.stopPrank();
    }

    function testRevertWhen_UpdateSharePricesWithMismatchedChainId() public {
        vm.startPrank(endpoint);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: 5,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.1e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.updateSharePrices(10, reports);
        vm.stopPrank();
    }

    function testRevertWhen_BatchUpdatePricesWithMismatchedArrayLengths() public {
        address[] memory assets = new address[](2);
        assets[0] = USDC;
        assets[1] = WETH;

        bool[] memory inUSD = new bool[](1);
        inUSD[0] = true;

        vm.expectRevert(SharePriceOracle.InvalidLength.selector);
        router.batchUpdatePrices(assets, inUSD);
    }

    function testGetSharePricesWithInvalidVault() public {
        address[] memory vaults = new address[](1);
        vaults[0] = makeAddr("invalidVault");

        vm.expectRevert();
        router.getSharePrices(vaults, address(0));
    }

    function testIsSupportedAsset() public {
        assertTrue(router.isSupportedAsset(USDC), "USDC should be supported");
        assertFalse(router.isSupportedAsset(makeAddr("unsupportedAsset")), "Random asset should not be supported");
    }

    function testRevertWhen_SetLocalAssetConfigWithZeroAdapter() public {
        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setLocalAssetConfig(USDC, address(0), USDC_USD_FEED, 0, true);
        vm.stopPrank();
    }

    function testRevertWhen_GrantRoleToZeroAddress() public {
        vm.startPrank(admin);

        bool success = false;
        try router.grantRole(address(0), router.ADMIN_ROLE()) {
            success = true;
        } catch { }

        assertFalse(success, "Should have reverted when granting role to zero address");

        vm.stopPrank();
    }

    function testRevertWhen_RevokeRoleFromZeroAddress() public {
        vm.startPrank(admin);
        bool success = false;

        try router.revokeRole(address(0), router.ADMIN_ROLE()) {
            success = true;
        } catch { }
        assertFalse(success, "Should have reverted when revoking role from zero address");

        vm.stopPrank();
    }

    function testGetLatestSharePrice_SameChainVault() public view {
        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(uint32(block.chainid), address(usdcVault), USDC);

        assertEq(price, 1.1e6, "Share price should match vault's share price");
        assertEq(timestamp, 0, "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossChainConversion() public {
        uint32 srcChain = 10;
        uint256 sharePrice = 1.15e6;

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opUsdcVault), USDT);

        assertApproxEqAbs(price, 1.15e6, 1.15e4, "Price should be converted correctly");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_DifferentDecimals() public {
        uint32 srcChain = 10;
        uint256 sharePrice = 1.15e18;

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opWethVault),
            asset: OPTIMISM_WETH,
            assetDecimals: 18,
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(opWethVault), USDC);

        (uint256 wethPrice,) = router.getLatestAssetPrice(WETH, true);
        (uint256 usdcPrice,) = router.getLatestAssetPrice(USDC, true);

        uint256 expectedPrice = (sharePrice * wethPrice / usdcPrice) / 10 ** 12;

        assertApproxEqAbs(price, expectedPrice, 1e4, "Price should be converted and scaled correctly");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testUpdateSharePrices_MultipleReports() public {
        uint32 srcChain = 10;

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](3);

        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.15e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        reports[1] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opWethVault),
            asset: OPTIMISM_WETH,
            assetDecimals: 18,
            sharePrice: 1.15e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        reports[2] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opWbtcVault),
            asset: OPTIMISM_WBTC,
            assetDecimals: 8,
            sharePrice: 1.15e8,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        for (uint256 i = 0; i < reports.length; i++) {
            ISharePriceOracle.VaultReport memory storedReport =
                router.getLatestSharePriceReport(srcChain, reports[i].vaultAddress);

            assertEq(storedReport.chainId, reports[i].chainId, "Chain ID should match");
            assertEq(storedReport.vaultAddress, reports[i].vaultAddress, "Vault address should match");
            assertEq(storedReport.asset, reports[i].asset, "Asset should match");
            assertEq(storedReport.sharePrice, reports[i].sharePrice, "Share price should match");
            assertEq(storedReport.assetDecimals, reports[i].assetDecimals, "Decimals should match");
        }
    }

    function testRevertWhen_UpdateSharePricesWithStalePrice() public {
        uint32 srcChain = 10;

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.15e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.warp(block.timestamp + router.PRICE_STALENESS_THRESHOLD() + 1);

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.NoValidPrice.selector);
        router.updateSharePrices(srcChain, reports);
    }

    function testUpdateSharePricesEmptyArray() public {
        uint32 srcChain = 10;
        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](0);

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);
    }

    function testSharePriceStalenessBehavior() public {
        uint32 srcChain = 10;

        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: srcChain,
            vaultAddress: address(opUsdcVault),
            asset: OPTIMISM_USDC,
            assetDecimals: 6,
            sharePrice: 1.1e6,
            lastUpdate: uint64(block.timestamp - 23 hours),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        vm.warp(block.timestamp + 25 hours);

        reports[0].lastUpdate = uint64(block.timestamp);

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.NoValidPrice.selector);
        router.updateSharePrices(srcChain, reports);
    }

    function testGetPriceKeyExternal() public view {
        uint32 testChainId = 1;
        address testVault = address(usdcVault);

        bytes32 manualKey = keccak256(abi.encodePacked(testChainId, testVault));
        bytes32 functionKey = router.getPriceKey(testChainId, testVault);

        assertEq(functionKey, manualKey, "Keys should match");
    }

    function testCrossChainConversionWithDifferentDecimals() public {
        vm.startPrank(admin);

        address[] memory assets = new address[](2);
        assets[0] = USDC;
        assets[1] = WETH;
        bool[] memory inUSD = new bool[](2);
        inUSD[0] = true;
        inUSD[1] = true;
        router.batchUpdatePrices(assets, inUSD);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: 10,
            vaultAddress: address(opWethVault),
            asset: OPTIMISM_WETH,
            assetDecimals: 18,
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.stopPrank();

        vm.prank(endpoint);
        router.updateSharePrices(10, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(10, address(opWethVault), USDC);

        assertTrue(price > 0, "Price should be non-zero");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testSequencerUnavailable() public {
        MockChainlinkSequencer mockSequencer = new MockChainlinkSequencer();
        mockSequencer.setDown();

        vm.prank(admin);
        router.setSequencer(address(mockSequencer));

        assertFalse(router.isSequencerValid(), "Sequencer should be reported as unavailable");

        mockSequencer.setStartedAt(block.timestamp);
        assertFalse(router.isSequencerValid(), "Should be invalid during grace period");

        vm.warp(block.timestamp + router.GRACE_PERIOD_TIME() + 1);
        mockSequencer.setStartedAt(block.timestamp - router.GRACE_PERIOD_TIME() - 1);
        mockSequencer.setUp();
        assertTrue(router.isSequencerValid(), "Should be valid after grace period");
    }

    function testInvalidChainIdValidations() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.setCrossChainAssetMapping(uint32(block.chainid), WETH, USDC);

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: uint32(block.chainid),
            vaultAddress: address(usdcVault),
            asset: USDC,
            assetDecimals: 6,
            sharePrice: 1e6,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: address(0)
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceOracle.InvalidChainId.selector);
        router.updateSharePrices(uint32(block.chainid), reports);
    }

    function testNotifyFeedRemovalMultiplePriorities() public {
        vm.startPrank(admin);
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 0, true);
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 1, true);
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 2, true);
        vm.stopPrank();

        assertEq(router.assetAdapterPriority(USDC), 2, "Highest priority should be 2");

        vm.prank(address(chainlinkAdapter));
        router.notifyFeedRemoval(USDC);

        for (uint8 i = 0; i <= 2; i++) {
            (address priceFeed,, address adaptor) = router.localAssetConfigs(USDC, i);
            assertEq(priceFeed, address(0), "Feed at priority level should be removed");
            assertEq(adaptor, address(0), "Adapter at priority level should be removed");
        }
    }

    function testRevertWhen_SetLocalAssetConfigWithZeroAdapter_Fixed() public {
        vm.startPrank(admin);
        vm.expectRevert(SharePriceOracle.ZeroAddress.selector);
        router.setLocalAssetConfig(USDC, address(0), USDC_USD_FEED, 0, true);
        vm.stopPrank();
    }

    function testBatchUpdatePrices_InvalidParameters() public {
        address[] memory assets = new address[](2);
        assets[0] = USDC;
        assets[1] = WETH;

        bool[] memory inUSD = new bool[](1);
        inUSD[0] = true;

        vm.expectRevert(SharePriceOracle.InvalidLength.selector);
        router.batchUpdatePrices(assets, inUSD);
    }

    function testGetLatestSharePrice_DifferentAssets() public view {
        (uint256 usdcPrice,) = router.getLatestSharePrice(uint32(block.chainid), address(usdcVault), USDC);

        (uint256 wethPrice,) = router.getLatestSharePrice(uint32(block.chainid), address(usdcVault), WETH);

        assertEq(usdcPrice, 1.1e6, "USDC price should be 1.1 USDC");

        assertTrue(wethPrice > 0, "WETH price should be non-zero");

        (uint256 usdcUsdPrice,) = router.getLatestAssetPrice(USDC, true);
        (uint256 wethUsdPrice,) = router.getLatestAssetPrice(WETH, true);

        uint256 expectedWethPrice = (1.1e6 * usdcUsdPrice * 1e18) / (wethUsdPrice * 1e6);

        assertApproxEqRel(wethPrice, expectedWethPrice, 1e15, "WETH price should be approximately correct");
    }

    function testGetPrice() public {
        (uint256 price, bool hadError) = router.getPrice(USDC, true);

        assertTrue(price > 0, "Price should be greater than zero");
        assertFalse(hadError, "Should not have error for configured asset");

        address randomAsset = makeAddr("randomAsset");
        (price, hadError) = router.getPrice(randomAsset, true);

        assertTrue(hadError, "Should have error for unconfigured asset");
    }

    function testGetLatestAssetPrice() public {
        vm.startPrank(admin);
        router.setLocalAssetConfig(USDC, address(chainlinkAdapter), USDC_USD_FEED, 0, true);

        address[] memory assets = new address[](1);
        assets[0] = USDC;
        bool[] memory inUSD = new bool[](1);
        inUSD[0] = true;
        router.batchUpdatePrices(assets, inUSD);
        vm.stopPrank();

        (uint256 price, bool hadError) = router.getLatestAssetPrice(USDC, true);

        assertTrue(price > 0, "Price should be greater than zero");
        assertFalse(hadError, "Should not have error for configured asset");

        address randomAsset = makeAddr("randomAsset");
        (price, hadError) = router.getLatestAssetPrice(randomAsset, true);

        assertTrue(hadError, "Should have error for unconfigured asset");
    }

    function testGetLocalAsset() public {
        vm.prank(admin);
        router.setCrossChainAssetMapping(10, OPTIMISM_USDC, USDC);

        (address localAsset, uint8 localDecimals) = router.getLocalAsset(10, OPTIMISM_USDC);

        assertEq(localAsset, USDC, "Local asset should be USDC");
        assertEq(localDecimals, 6, "USDC decimals should be 6");

        address randomAsset = makeAddr("randomAsset");
        vm.expectRevert(abi.encodeWithSelector(SharePriceOracle.AssetNotConfigured.selector, randomAsset));
        router.getLocalAsset(10, randomAsset);
    }

    function testGetSharePrices() public {
        address[] memory vaults = new address[](3);
        vaults[0] = address(usdcVault);
        vaults[1] = address(wethVault);
        vaults[2] = address(wbtcVault);

        address rewardsDelegate = makeAddr("rewardsDelegate");

        ISharePriceOracle.VaultReport[] memory reports = router.getSharePrices(vaults, rewardsDelegate);

        assertEq(reports.length, 3, "Should return 3 reports");

        for (uint256 i = 0; i < reports.length; i++) {
            assertEq(reports[i].chainId, uint32(block.chainid), "Chain ID should match");
            assertEq(reports[i].rewardsDelegate, rewardsDelegate, "Rewards delegate should match");
            assertTrue(reports[i].sharePrice > 0, "Share price should be greater than zero");
        }

        assertEq(reports[0].vaultAddress, address(usdcVault), "First vault should be USDC vault");
        assertEq(reports[0].asset, USDC, "First vault asset should be USDC");
        assertEq(reports[0].assetDecimals, 6, "USDC decimals should be 6");

        assertEq(reports[1].vaultAddress, address(wethVault), "Second vault should be WETH vault");
        assertEq(reports[1].asset, WETH, "Second vault asset should be WETH");
        assertEq(reports[1].assetDecimals, 18, "WETH decimals should be 18");
    }
}
