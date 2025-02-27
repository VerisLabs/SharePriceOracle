// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Test } from "forge-std/Test.sol";
import { SharePriceRouter } from "../../src/SharePriceRouter.sol";
import { ChainlinkAdapter } from "../../src/adapters/Chainlink.sol";
import { Api3Adapter } from "../../src/adapters/Api3.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";
import { VaultReport } from "../../src/interfaces/ISharePriceRouter.sol";
import { Ownable } from "solady/auth/Ownable.sol";
import { MockVault } from "../mocks/MockVault.sol";
import { MockChainlinkSequencer } from "../mocks/MockChainlinkSequencer.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { MockChainlinkFeed } from "../mocks/MockChainlinkFeed.sol";

// Constants for BASE network
address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
address constant WETH = 0x4200000000000000000000000000000000000006;
address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
address constant DAI = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;

// Chainlink price feed addresses on BASE
address constant ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
address constant BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
address constant DAI_USD_FEED = 0x591e79239a7d679378eC8c847e5038150364C78F;
address constant USDC_USD_FEED = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

// API3 price feed addresses on BASE (if available)
address constant API3_ETH_USD_FEED = 0x5b0cf2b36a65a6BB085D501B971e4c102B9Cd473;
address constant API3_BTC_USD_FEED = 0x041a131Fa91Ad61dD85262A42c04975986580d50;

// Heartbeat values (in seconds)
uint256 constant CHAINLINK_HEARTBEAT = 86_400; // 24 hours
uint256 constant API3_HEARTBEAT = 14_400; // 4 hours

// Add Optimism USDC address at the top with other constants
address constant OPTIMISM_USDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // USDC.e (bridged)

contract SharePriceRouterTest is Test {
    // Test contracts
    SharePriceRouter public router;
    ChainlinkAdapter public chainlinkAdapter;
    Api3Adapter public api3Adapter;

    // Test vaults
    MockVault public usdcVault;
    MockVault public wethVault;
    MockVault public wbtcVault;
    MockVault public daiVault;

    // Test accounts
    address public admin;
    address public updater;
    address public endpoint;
    address public user;

    function setUp() public {
        string memory baseRpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(baseRpcUrl);

        // Setup test accounts
        admin = makeAddr("admin");
        updater = makeAddr("updater");
        endpoint = makeAddr("endpoint");
        user = makeAddr("user");

        // Deploy router with admin as owner
        vm.prank(admin);
        router = new SharePriceRouter(admin, ETH_USD_FEED, USDC, WBTC, WETH);

        // Deploy adapters
        chainlinkAdapter = new ChainlinkAdapter(
            admin,
            address(router),
            address(router) // Router is now its own router
        );

        api3Adapter = new Api3Adapter(
            admin,
            address(router),
            address(router), // Router is now its own router
            WETH
        );

        // Deploy mock vaults with correct decimals for each asset
        // USDC: 6 decimals
        usdcVault = new MockVault(USDC, 6, 1.1e6); // 1.1 USDC
        // WETH: 18 decimals
        wethVault = new MockVault(WETH, 18, 1.1e18); // 1.1 ETH
        // WBTC: 8 decimals
        wbtcVault = new MockVault(WBTC, 8, 1.1e8); // 1.1 BTC
        // DAI: 18 decimals
        daiVault = new MockVault(DAI, 18, 1.1e18); // 1.1 DAI

        // Setup roles
        vm.startPrank(admin);
        router.grantRole(updater, router.UPDATER_ROLE());
        router.grantRole(endpoint, router.ENDPOINT_ROLE());
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
        router.grantRole(user, router.UPDATER_ROLE());
        router.revokeRole(user, router.UPDATER_ROLE());
        vm.stopPrank();

        assertFalse(router.hasAnyRole(user, router.UPDATER_ROLE()), "Role should be revoked");
    }

    function testRevertGrantRole_InvalidRole() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceRouter.InvalidRole.selector);
        router.grantRole(user, 0);
    }

    // Adapter management tests
    function testAddAdapter() public {
        vm.prank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);

        assertEq(router.adapterPriorities(address(chainlinkAdapter)), 1, "Adapter priority should be set");
    }

    function testRevertAddAdapter_AlreadyExists() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);

        vm.expectRevert(SharePriceRouter.AdapterAlreadyExists.selector);
        router.addAdapter(address(chainlinkAdapter), 2);
        vm.stopPrank();
    }

    function testRevertAddAdapter_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceRouter.ZeroAddress.selector);
        router.addAdapter(address(0), 1);
    }

    function testRemoveAdapter() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.removeAdapter(address(chainlinkAdapter));
        vm.stopPrank();

        assertEq(router.adapterPriorities(address(chainlinkAdapter)), 0, "Adapter should be removed");
    }

    function testRevertRemoveAdapter_NotFound() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceRouter.AdapterNotFound.selector);
        router.removeAdapter(address(chainlinkAdapter));
    }

    // Asset category tests
    function testSetAssetCategory() public {
        vm.prank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        assertEq(
            uint256(router.assetCategories(USDC)),
            uint256(SharePriceRouter.AssetCategory.STABLE),
            "Asset category should be set"
        );
    }

    function testRevertSetAssetCategory_NotAdmin() public {
        vm.prank(user);
        vm.expectRevert();
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
    }

    function testRevertSetAssetCategory_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceRouter.ZeroAddress.selector);
        router.setAssetCategory(address(0), SharePriceRouter.AssetCategory.STABLE);
    }

    function testRevertSetAssetCategory_InvalidCategory() public {
        vm.prank(admin);
        vm.expectRevert(SharePriceRouter.InvalidAssetType.selector);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.UNKNOWN);
    }

    // Share price tests
    function testGetLatestSharePrice_USDC() public {
        // Set USDC category
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        // Add adapters
        router.addAdapter(address(chainlinkAdapter), 1);

        // Grant roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feed for USDC
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, 86_400, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(usdcVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals

        // Allow for a small deviation (0.1%) in price
        uint256 maxDelta = expectedSharePrice / 1000; // 0.1% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current block");
    }

    function testGetLatestSharePrice_DAI_to_USDC() public {
        vm.startPrank(admin);
        // Set asset categories
        router.setAssetCategory(DAI, SharePriceRouter.AssetCategory.STABLE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        // Add adapters
        router.addAdapter(address(chainlinkAdapter), 1);
        router.addAdapter(address(api3Adapter), 2);

        // Grant roles to test contract
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds for DAI and USDC
        chainlinkAdapter.addAsset(DAI, DAI_USD_FEED, 86_400, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, 86_400, true);

        // Create DAI vault with 1.1 DAI per share
        uint256 sharePrice = 1.1e18; // DAI uses 18 decimals
        daiVault = new MockVault(DAI, 18, sharePrice);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(daiVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals

        // Allow for a small deviation (0.1%) in price due to conversion
        uint256 maxDelta = expectedSharePrice / 1000; // 0.1% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_ETH_to_USDC() public {
        vm.startPrank(admin);
        // Set asset categories
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        // Add adapters with different priorities
        router.addAdapter(address(chainlinkAdapter), 1); // Primary
        router.addAdapter(address(api3Adapter), 2); // Secondary

        // Grant roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        api3Adapter.addAsset(WETH, "ETH/USD", API3_ETH_USD_FEED, API3_HEARTBEAT, true);

        // Get current ETH/USD price to calculate expected value
        (uint256 ethPrice,,) = router.getLatestPrice(WETH, true);
        (uint256 usdcPrice,,) = router.getLatestPrice(USDC, true);

        // Create ETH vault with 1.1 ETH per share
        uint256 sharePrice = 1.1e18; // ETH uses 18 decimals
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();

        wethVault = new MockVault(WETH, 18, sharePrice);

        uint256 expectedSharePrice = (sharePrice * ethPrice) / (usdcPrice * 10 ** (wethDecimals - usdcDecimals));

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(wethVault), USDC);

        // Allow for a small deviation (2%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = (expectedSharePrice * 2) / 100; // 2% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossCategory_ETH_to_BTC() public {
        vm.startPrank(admin);
        // Set asset categories
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);

        // Add adapters with different priorities
        router.addAdapter(address(chainlinkAdapter), 1); // Primary
        router.addAdapter(address(api3Adapter), 2); // Secondary

        // Grant roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(WBTC, BTC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        api3Adapter.addAsset(WETH, "ETH/USD", API3_ETH_USD_FEED, API3_HEARTBEAT, true);
        api3Adapter.addAsset(WBTC, "WBTC/USD", API3_BTC_USD_FEED, API3_HEARTBEAT, true);

        // Create ETH vault with 1.1 ETH per share
        uint256 sharePrice = 1.1e18; // ETH uses 18 decimals
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
        wethVault = new MockVault(WETH, 18, sharePrice);

        // Get current prices to calculate expected value
        (uint256 ethPrice,,) = router.getLatestPrice(WETH, true);
        (uint256 btcPrice,,) = router.getLatestPrice(WBTC, true);

        // Calculate expected price: (1.1 * ETH/USD) / (BTC/USD) in BTC decimals
        uint256 expectedSharePrice = (sharePrice * ethPrice) / (btcPrice * 10 ** (wethDecimals - wbtcDecimals));

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(wethVault), WBTC);

        // Allow for a larger deviation (1%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = expectedSharePrice / 100; // 1% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossCategory_BTC_to_USDC() public {
        vm.startPrank(admin);
        // Set asset categories
        router.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        // Add adapters with different priorities
        router.addAdapter(address(chainlinkAdapter), 1); // Primary
        router.addAdapter(address(api3Adapter), 2); // Secondary

        // Grant roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(WBTC, BTC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        api3Adapter.addAsset(WBTC, "WBTC/USD", API3_BTC_USD_FEED, API3_HEARTBEAT, true);

        // Create BTC vault with 1.1 BTC per share
        uint256 sharePrice = 1.1e8; // BTC uses 8 decimals
        uint8 btcDecimals = IERC20Metadata(WBTC).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        wbtcVault = new MockVault(WBTC, 8, sharePrice);

        // Get current BTC/USD price to calculate expected value
        (uint256 btcPrice,,) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice,,) = router.getLatestPrice(USDC, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(wbtcVault), USDC);

        uint256 expectedSharePrice = (sharePrice * btcPrice) / (usdcPrice * 10 ** (btcDecimals - usdcDecimals));

        // Allow for a larger deviation (2%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = (expectedSharePrice * 2) / 100; // 2% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_CrossCategory_USDC_to_BTC() public {
        vm.startPrank(admin);
        // Set asset categories
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);

        // Add adapters with different priorities
        router.addAdapter(address(chainlinkAdapter), 1); // Primary
        router.addAdapter(address(api3Adapter), 2); // Secondary

        // Grant roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(WBTC, BTC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        api3Adapter.addAsset(WBTC, "WBTC/USD", API3_BTC_USD_FEED, API3_HEARTBEAT, true);

        // Create USDC vault with 1.1 USDC per share
        uint256 sharePrice = 1.1e6; // USDC uses 6 decimals
        usdcVault = new MockVault(USDC, 6, sharePrice);

        // Get current prices to calculate expected value
        (uint256 btcPrice,,) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice,,) = router.getLatestPrice(USDC, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), address(usdcVault), WBTC);

        uint256 shareUsdValue = (sharePrice * usdcPrice) / 1e6;
        uint256 expectedSharePrice = (shareUsdValue * 1e8) / btcPrice;

        // Allow for a larger deviation (1%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = expectedSharePrice / 100; // 1% of expected price
        assertApproxEqAbs(
            actualSharePrice, expectedSharePrice, maxDelta, "Share price should be close to expected value"
        );
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
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

        vm.startPrank(admin);
        router.setSequencer(address(mockSequencer));
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Mock the sequencer being down for a while
        mockSequencer.setStartedAt(block.timestamp - router.GRACE_PERIOD_TIME() - 1);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(usdcVault), USDC);

        assertEq(price, 1.1e6, "Should return last valid price when sequencer is down");
        assertTrue(timestamp > 0, "Should have valid timestamp from last price");

        // Verify that the sequencer is actually down
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
        vm.expectRevert(abi.encodeWithSelector(SharePriceRouter.InvalidChainId.selector, uint32(block.chainid)));
        router.setCrossChainAssetMapping(uint32(block.chainid), srcAsset, localAsset);
    }

    function testRevertSetCrossChainAssetMapping_ZeroAddresses() public {
        uint32 srcChain = 10;

        vm.startPrank(admin);
        vm.expectRevert(SharePriceRouter.ZeroAddress.selector);
        router.setCrossChainAssetMapping(srcChain, address(0), makeAddr("local"));

        vm.expectRevert(SharePriceRouter.ZeroAddress.selector);
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
        // Use a different chain ID than the current chain ID (which is Base/8453)
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address asset = makeAddr("asset");
        address localAsset = WETH; // Use a real token that exists on the chain
        uint256 sharePrice = 1e18;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: asset,
            assetDecimals: 18
        });

        // Mock the chain ID to be different from srcChain
        vm.chainId(8453); // Base chain ID

        // Set up the cross-chain asset mapping before calling updateSharePrices
        vm.startPrank(admin);
        router.setCrossChainAssetMapping(srcChain, asset, localAsset);
        vm.stopPrank();

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        VaultReport memory stored = router.getLatestSharePriceReport(srcChain, vaultAddr);

        // Verify the stored report matches what we sent
        assertEq(stored.chainId, srcChain);
        assertEq(stored.vaultAddress, vaultAddr);
        assertEq(stored.asset, asset);
        assertEq(stored.sharePrice, sharePrice);
        assertEq(stored.assetDecimals, 18);
    }

    function testUpdateSharePrices_WithLocalEquivalent() public {
        // Use a different chain ID than the current chain ID (which is Base/8453)
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address asset = WETH; // Use a real asset that has a local equivalent
        uint256 sharePrice = 1e18;

        // Set up cross-chain asset mapping
        vm.startPrank(admin);
        router.setCrossChainAssetMapping(srcChain, asset, WETH);
        vm.stopPrank();

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: asset,
            assetDecimals: 18
        });

        // Mock the chain ID to be different from srcChain
        vm.chainId(8453); // Base chain ID

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        VaultReport memory stored = router.getLatestSharePriceReport(srcChain, vaultAddr);
        assertEq(stored.sharePrice, sharePrice, "Share price should be stored");
        assertEq(router.vaultChainIds(vaultAddr), srcChain, "Chain ID should be stored");
    }

    function testRevertUpdateSharePrices_InvalidChainId() public {
        uint32 srcChain = 10; // Different chain ID
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            chainId: uint32(block.chainid), // Same as current chain
            rewardsDelegate: address(0),
            vaultAddress: makeAddr("vault"),
            asset: makeAddr("asset"),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        vm.expectRevert(abi.encodeWithSelector(SharePriceRouter.InvalidChainId.selector, uint32(block.chainid)));
        router.updateSharePrices(srcChain, reports);
    }

    function testRevertUpdateSharePrices_TooManyReports() public {
        VaultReport[] memory reports = new VaultReport[](router.MAX_REPORTS() + 1);

        vm.prank(endpoint);
        vm.expectRevert(SharePriceRouter.ExceedsMaxReports.selector);
        router.updateSharePrices(10, reports);
    }

    function testRevertUpdateSharePrices_NotEndpoint() public {
        vm.prank(user);
        vm.expectRevert();
        router.updateSharePrices(10, new VaultReport[](1));
    }

    // Price Conversion Tests
    function testConvertStoredPrice_SameAsset() public {
        // Test converting price when source and destination are the same asset
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint64 timestamp) = router.convertStoredPrice(1e6, USDC, USDC);
        assertEq(price, 1e6, "Price should remain unchanged for same asset");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testRevertConvertStoredPrice_UnknownCategory() public {
        address randomAsset = makeAddr("random");

        vm.expectRevert(SharePriceRouter.InvalidAssetType.selector);
        router.convertStoredPrice(1e18, randomAsset, USDC);
    }

    function testConvertStoredPrice_CrossCategory() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint64 timestamp) = router.convertStoredPrice(1e18, WETH, USDC);
        assertTrue(price > 0, "Converted price should be non-zero");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    // Price Validation Tests
    function testGetPrice_ValidPrice() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint256 errorCode) = router.getPrice(USDC, true);

        assertTrue(price > 0, "Should return valid price");
        assertEq(errorCode, 0, "Should return no error");
    }

    function testGetPrice_NoAdapters() public {
        vm.expectRevert(SharePriceRouter.NoAdaptersConfigured.selector);
        router.getLatestPrice(USDC, true);
    }

    function testGetPrice_NoValidPrice() public {
        vm.prank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);

        vm.expectRevert(SharePriceRouter.NoValidPrice.selector);
        router.getLatestPrice(makeAddr("random"), true);
    }

    function testGetPrice_StoredPriceFallback() public {
        // First set up the adapter and get an initial price
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Get and store initial price
        (uint256 initialPrice,,) = router.getLatestPrice(USDC, true);
        vm.prank(updater);
        router.updatePrice(USDC, true);

        // Remove adapter and verify stored price is returned
        vm.startPrank(admin);
        router.removeAdapter(address(chainlinkAdapter));
        vm.stopPrank();

        // Add a new adapter but don't configure it for USDC
        vm.prank(admin);
        router.addAdapter(address(api3Adapter), 1);

        // Try to get price - should fall back to stored price
        (uint256 price, uint256 timestamp, bool isUSD) = router.getLatestPrice(USDC, true);
        assertEq(price, initialPrice, "Should return stored price");
        assertTrue(isUSD, "Should maintain USD flag");
        assertTrue(timestamp > 0, "Should have valid timestamp");
    }

    function testGetLatestSharePriceReport() public {
        // Use a different chain ID than the current chain ID (which is Base/8453)
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address asset = makeAddr("asset");
        uint256 sharePrice = 1e18;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: asset,
            assetDecimals: 18
        });

        // Mock the chain ID to be different from srcChain
        vm.chainId(8453); // Base chain ID

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        VaultReport memory report = router.getLatestSharePriceReport(srcChain, vaultAddr);
        assertEq(report.sharePrice, sharePrice, "Should return correct share price");
        assertEq(report.chainId, srcChain, "Should return correct chain ID");
        assertEq(report.vaultAddress, vaultAddr, "Should return correct vault address");
    }

    function testNotifyFeedRemoval() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        vm.stopPrank();

        vm.prank(address(chainlinkAdapter));
        router.notifyFeedRemoval(USDC);

        assertEq(router.adapterPriorities(address(chainlinkAdapter)), 0, "Adapter should be removed");
    }

    function testRevertNotifyFeedRemoval_AdapterNotFound() public {
        vm.prank(address(chainlinkAdapter));
        vm.expectRevert(SharePriceRouter.AdapterNotFound.selector);
        router.notifyFeedRemoval(USDC);
    }

    // Cross-Chain Asset Mapping Tests
    function testMultipleMappings() public {
        address srcAsset1 = makeAddr("srcAsset1");
        address srcAsset2 = makeAddr("srcAsset2");
        address localAsset = makeAddr("localAsset");
        uint32 srcChain1 = 10;
        uint32 srcChain2 = 20;

        vm.startPrank(admin);
        // Map two different source assets to the same local asset
        router.setCrossChainAssetMapping(srcChain1, srcAsset1, localAsset);
        router.setCrossChainAssetMapping(srcChain2, srcAsset2, localAsset);
        vm.stopPrank();

        bytes32 key1 = keccak256(abi.encodePacked(srcChain1, srcAsset1));
        bytes32 key2 = keccak256(abi.encodePacked(srcChain2, srcAsset2));

        assertEq(router.crossChainAssetMap(key1), localAsset, "First mapping should be set");
        assertEq(router.crossChainAssetMap(key2), localAsset, "Second mapping should be set");
    }

    // Adapter Management Tests
    function testAdapterPriority() public {
        vm.startPrank(admin);
        // Add two adapters with different priorities
        router.addAdapter(address(chainlinkAdapter), 2); // Lower priority
        router.addAdapter(address(api3Adapter), 1); // Higher priority

        // Set up asset and roles
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Configure both adapters for WETH
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        api3Adapter.addAsset(WETH, "ETH/USD", API3_ETH_USD_FEED, API3_HEARTBEAT, true);

        // Get price - should use API3 due to higher priority
        (uint256 price,, bool isUSD) = router.getLatestPrice(WETH, true);
        assertTrue(price > 0, "Should get valid price");
        assertTrue(isUSD, "Price should be in USD");
    }

    function testAdapterRemovalDuringPriceQuery() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add asset to adapter
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Get initial price
        (uint256 initialPrice,,) = router.getLatestPrice(WETH, true);
        assertTrue(initialPrice > 0, "Should get initial price");

        // Store the price
        vm.prank(updater);
        router.updatePrice(WETH, true);

        // Remove adapter
        vm.prank(admin);
        router.removeAdapter(address(chainlinkAdapter));

        // Add a new adapter but don't configure it for WETH
        vm.prank(admin);
        router.addAdapter(address(api3Adapter), 1);

        // Try to get price - should use stored price
        (uint256 price,, bool isUSD) = router.getLatestPrice(WETH, true);
        assertEq(price, initialPrice, "Should return stored price");
        assertTrue(isUSD, "Price should be in USD");
    }

    function testAdapterStateAfterRemoval() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);

        // Verify adapter was added
        assertEq(router.adapterPriorities(address(chainlinkAdapter)), 1, "Priority should be set");

        // Remove adapter
        router.removeAdapter(address(chainlinkAdapter));
        vm.stopPrank();

        // Verify adapter was removed
        assertEq(router.adapterPriorities(address(chainlinkAdapter)), 0, "Priority should be cleared");

        // Verify adapter cannot be removed again
        vm.startPrank(admin);
        vm.expectRevert(SharePriceRouter.AdapterNotFound.selector);
        router.removeAdapter(address(chainlinkAdapter));
        vm.stopPrank();
    }

    function testGetLatestSharePrice_ZeroAddresses() public view {
        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(0), address(0));

        assertEq(price, 0, "Price should be 0 for zero addresses");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_InvalidVault() public {
        // with invalid vault but valid destination asset
        (uint256 price, uint64 timestamp) =
            router.getLatestSharePrice(router.chainId(), makeAddr("nonexistentVault"), USDC);

        assertEq(price, 0, "Price should be 0 for invalid vault");
        assertEq(timestamp, 0, "Timestamp should be 0 for invalid vault");
    }

    function testGetLatestSharePrice_StalePrice() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        vm.prank(updater);
        router.updatePrice(USDC, true);

        uint32 srcChain = 10;
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e6,
            lastUpdate: uint64(block.timestamp - router.PRICE_STALENESS_THRESHOLD() - 1),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: address(usdcVault),
            asset: USDC,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        vm.warp(block.timestamp + router.PRICE_STALENESS_THRESHOLD() + 1);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, address(usdcVault), USDC);

        assertEq(price, 0, "Price should be 0 for stale data");
        assertEq(timestamp, 0, "Timestamp should be 0 for stale data");
    }

    function testGetLatestSharePrice_CrossChainWithoutMapping() public {
        uint32 srcChain = 10;
        address srcAsset = makeAddr("srcAsset");

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 1e18,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: makeAddr("vault"),
            asset: srcAsset,
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, reports[0].vaultAddress, USDC);

        assertEq(price, 0, "Price should be 0 without mapping");
        assertEq(timestamp, 0, "Timestamp should be 0");
    }

    function testGetLatestSharePrice_MultipleAdapterFailure() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        router.addAdapter(address(chainlinkAdapter), 1);
        router.addAdapter(address(api3Adapter), 2);
        vm.stopPrank();

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(wethVault), USDC);

        assertEq(price, 0, "Price should be 0 when all adapters fail");
        assertEq(timestamp, 0, "Timestamp should be 0 when all adapters fail");
    }

    function testGetLatestSharePrice_DecimalOverflow() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        uint256 maxSharePrice = 1e30;
        MockVault extremeVault = new MockVault(WETH, 18, maxSharePrice);

        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        vm.prank(updater);
        router.updatePrice(WETH, true);
        vm.prank(updater);
        router.updatePrice(USDC, true);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(extremeVault), USDC);

        assertTrue(price > 0, "Should handle large numbers");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");
    }

    function testGetLatestSharePrice_SequencerDown() public {
        MockChainlinkSequencer mockSequencer = new MockChainlinkSequencer();
        mockSequencer.setDown();

        vm.startPrank(admin);
        router.setSequencer(address(mockSequencer));
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        vm.warp(block.timestamp + router.PRICE_STALENESS_THRESHOLD() + 1);

        mockSequencer.setStartedAt(block.timestamp - router.GRACE_PERIOD_TIME() - 1);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(usdcVault), USDC);

        assertEq(price, 1.1e6, "Price should be last valid price when sequencer is down");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be last valid timestamp when sequencer is down");
    }

    function testGetLatestSharePrice_CircularConversion() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(WBTC, BTC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price1,) = router.getLatestSharePrice(router.chainId(), address(wethVault), WBTC);

        MockVault intermediateVault = new MockVault(WBTC, 8, price1);

        (uint256 price2,) = router.getLatestSharePrice(router.chainId(), address(intermediateVault), USDC);

        MockVault finalVault = new MockVault(USDC, 6, price2);
        (uint256 price3,) = router.getLatestSharePrice(router.chainId(), address(finalVault), WETH);

        uint256 originalPrice = 1.1e18;
        uint256 maxDelta = originalPrice * 2 / 100;
        assertApproxEqAbs(price3, originalPrice, maxDelta, "Circular conversion should approximately preserve value");
    }

    function testGetLatestSharePrice_MaximumPrecisionLoss() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        uint256 tinySharePrice = 1;
        MockVault tinyVault = new MockVault(WETH, 18, tinySharePrice);

        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(router.chainId(), address(tinyVault), USDC);

        assertEq(price, 0, "Price should be 0 due to precision loss");
        assertEq(timestamp, 0, "Timestamp should be 0 when price is lost");
    }

    function testIsSupportedAsset_NoAdapters() public view {
        assertFalse(router.isSupportedAsset(USDC), "Should return false when no adapters configured");
    }

    function testIsSupportedAsset_WithSupportedAsset() public {
        vm.startPrank(admin);
        // Add Chainlink adapter
        router.addAdapter(address(chainlinkAdapter), 1);

        // Configure adapter roles
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add USDC to Chainlink adapter
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        assertTrue(router.isSupportedAsset(USDC), "Should return true for supported asset");
    }

    function testIsSupportedAsset_WithUnsupportedAsset() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        assertFalse(router.isSupportedAsset(USDC), "Should return false for unsupported asset");
    }

    function testIsSupportedAsset_MultipleAdapters() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.addAdapter(address(api3Adapter), 2);

        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        api3Adapter.addAsset(WETH, "ETH/USD", API3_ETH_USD_FEED, API3_HEARTBEAT, true);

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        assertTrue(router.isSupportedAsset(WETH), "Should return true for asset supported by API3");
        assertTrue(router.isSupportedAsset(USDC), "Should return true for asset supported by Chainlink");
        assertFalse(
            router.isSupportedAsset(makeAddr("unsupported")),
            "Should return false for asset not supported by any adapter"
        );
    }

    function testIsSupportedAsset_AfterAdapterRemoval() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        assertTrue(router.isSupportedAsset(USDC), "Should be supported before adapter removal");

        vm.prank(admin);
        router.removeAdapter(address(chainlinkAdapter));

        assertFalse(router.isSupportedAsset(USDC), "Should not be supported after adapter removal");
    }

    function testIsSupportedAsset_ZeroAddress() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        assertFalse(router.isSupportedAsset(address(0)), "Should return false for zero address");
    }

    function testGetPrice_UnsupportedAsset() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Don't add any assets to adapter
        (uint256 price, uint256 errorCode) = router.getPrice(makeAddr("unsupported"), true);

        assertEq(price, 0, "Should return zero price");
        assertEq(errorCode, 1, "Should return error code 1");
    }

    function testGetPrice_StalePrice() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Store initial price
        vm.prank(updater);
        router.updatePrice(USDC, true);

        // Move time forward to make price stale
        vm.warp(block.timestamp + router.PRICE_STALENESS_THRESHOLD() + 1);

        (uint256 price, uint256 errorCode) = router.getPrice(USDC, true);

        assertEq(price, 0, "Should return zero price for stale data");
        assertEq(errorCode, 1, "Should return error code 1 for stale data");
    }

    function testGetPrice_WrongDenomination() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint256 errorCode) = router.getPrice(USDC, false);

        assertEq(price, 0, "Should return zero price for wrong denomination");
        assertEq(errorCode, 1, "Should return error code 1 for wrong denomination");
    }

    function testGetPrice_ZeroPrice() public {
        MockChainlinkFeed mockFeed = new MockChainlinkFeed(0, 8);
        mockFeed.setPrice(0);

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, address(mockFeed), CHAINLINK_HEARTBEAT, true);

        (uint256 price, uint256 errorCode) = router.getPrice(USDC, true);

        assertEq(price, 0, "Should return zero price");
        assertEq(errorCode, 1, "Should return error code 1");

        vm.expectRevert();
        router.getLatestPrice(USDC, true);
    }

    function testGetPrice_AdapterRemoval() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Get initial price
        (uint256 initialPrice, uint256 initialError) = router.getPrice(USDC, true);
        assertTrue(initialPrice > 0, "Should get initial price");
        assertEq(initialError, 0, "Should have no initial error");

        // Remove adapter
        vm.prank(admin);
        router.removeAdapter(address(chainlinkAdapter));

        (uint256 price, uint256 errorCode) = router.getPrice(USDC, true);

        assertEq(price, 0, "Should return zero price after adapter removal");
        assertEq(errorCode, 1, "Should return error code 1 after adapter removal");
    }

    function testGetLatestSharePrice_StoredPriceSameAsset() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        uint256 storedPrice = 1.5e6;
        uint64 storedTime = uint64(block.timestamp - 100);

        // Set up USDC configuration
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC); // Map Optimism USDC to Base USDC
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add USDC price feed
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: storedPrice,
            lastUpdate: storedTime,
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);

        router.getLatestPrice(USDC, true);
        uint256 expectedPrice = 2.25e6;

        assertEq(price, expectedPrice, "Should return stored price directly");
        assertTrue(timestamp > 0, "Should return stored timestamp");
    }

    function testCrossChainRate_SameAsset() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        uint256 storedPrice = 1.5e6; // Match USDC decimals (6)
        uint64 storedTime = uint64(block.timestamp - 100);

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: storedPrice,
            lastUpdate: storedTime,
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price,) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, storedPrice, "Price should be unchanged for same asset");
    }

    function testCrossChainRate_DifferentAssets() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        uint256 storedPrice = 1.5e6;
        uint64 storedTime = uint64(block.timestamp - 100);

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: storedPrice,
            lastUpdate: storedTime,
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price,) = router.getLatestSharePrice(srcChain, vaultAddr, WETH);
        assertTrue(price > 0, "Should return non-zero price after conversion");
    }

    function testCrossChainRate_UnmappedAssetBehavior() public {
        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 storedPrice = 1.5e6;
        uint64 storedTime = uint64(block.timestamp - 100);

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: storedPrice,
            lastUpdate: storedTime,
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: OPTIMISM_USDC,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Should return zero price for unmapped asset");
        assertEq(timestamp, 0, "Should return zero timestamp for unmapped asset");

        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, OPTIMISM_USDC, USDC);

        router.getLatestPrice(USDC, true);
        uint256 expectedPrice = 2.25e6;

        (price, timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, expectedPrice, "Should return price converted through USD");
        assertTrue(timestamp > 0, "Should return non-zero timestamp");
    }

    function testGetLatestPrice_InvalidDecimals() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        MockChainlinkFeed mockFeed = new MockChainlinkFeed(1e18, 77);
        chainlinkAdapter.addAsset(USDC, address(mockFeed), CHAINLINK_HEARTBEAT, true);

        vm.expectRevert();
        router.getLatestPrice(USDC, true);
    }

    function testCrossChainAssetMapping_MultipleChains() public {
        address asset1 = makeAddr("asset1");
        address asset2 = makeAddr("asset2");
        address localAsset = makeAddr("localAsset");
        uint32 chain1 = 10; // Optimism
        uint32 chain2 = 42_161; // Arbitrum

        vm.startPrank(admin);
        router.setCrossChainAssetMapping(chain1, asset1, localAsset);
        router.setCrossChainAssetMapping(chain2, asset2, localAsset);
        vm.stopPrank();

        bytes32 key1 = keccak256(abi.encodePacked(chain1, asset1));
        bytes32 key2 = keccak256(abi.encodePacked(chain2, asset2));

        assertEq(router.crossChainAssetMap(key1), localAsset, "First mapping should be set");
        assertEq(router.crossChainAssetMap(key2), localAsset, "Second mapping should be set");
    }

    function testConvertStoredPrice_ExtremeValues() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(WETH, ETH_USD_FEED, CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        uint256 largePrice = type(uint240).max;
        vm.expectRevert();
        router.convertStoredPrice(largePrice, WETH, USDC);

        uint256 smallPrice = 1;
        (uint256 price,) = router.convertStoredPrice(smallPrice, WETH, USDC);
        assertEq(price, 0, "Should handle very small prices gracefully");
    }

    function testAdapterPriority_DynamicUpdate() public {
        vm.startPrank(admin);
        router.addAdapter(address(chainlinkAdapter), 2);
        router.addAdapter(address(api3Adapter), 1);

        router.removeAdapter(address(api3Adapter));

        address newAdapter = makeAddr("newAdapter");
        router.addAdapter(newAdapter, 1);
        vm.stopPrank();

        assertEq(router.adapterPriorities(newAdapter), 1, "New adapter should have highest priority");
        assertEq(
            router.adapterPriorities(address(chainlinkAdapter)), 2, "Original adapter priority should remain unchanged"
        );
    }

    function testUpdateSharePrices_EmptyReports() public {
        VaultReport[] memory emptyReports = new VaultReport[](0);

        vm.prank(endpoint);
        router.updateSharePrices(10, emptyReports);
    }

    function testUpdateSharePrices_InvalidSharePrice() public {
        uint32 srcChain = 10;
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: 0,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: makeAddr("vault"),
            asset: makeAddr("asset"),
            assetDecimals: 18
        });

        vm.prank(endpoint);
        vm.expectRevert(SharePriceRouter.InvalidPrice.selector);
        router.updateSharePrices(srcChain, reports);
    }

    function testAssetCategory_Inheritance() public {
        address baseAsset = makeAddr("baseAsset");
        address derivedAsset = makeAddr("derivedAsset");

        vm.startPrank(admin);
        router.setAssetCategory(baseAsset, SharePriceRouter.AssetCategory.ETH_LIKE);

        router.setAssetCategory(derivedAsset, SharePriceRouter.AssetCategory.ETH_LIKE);
        vm.stopPrank();

        assertEq(
            uint256(router.assetCategories(baseAsset)),
            uint256(router.assetCategories(derivedAsset)),
            "Derived asset should inherit same category"
        );
    }

    function testPriceStaleness_EdgeCases() public {
        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        vm.prank(updater);
        router.updatePrice(USDC, true);

        vm.warp(block.timestamp + router.PRICE_STALENESS_THRESHOLD());
        (uint256 price, uint256 errorCode) = router.getPrice(USDC, true);
        assertEq(errorCode, 0, "Price should still be valid at staleness threshold");

        vm.warp(block.timestamp + 1);
        (price, errorCode) = router.getPrice(USDC, true);
        assertEq(errorCode, 1, "Price should be stale just past threshold");
    }

    function testDirectUsdConversion_InvalidSourcePrice() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 sharePrice = 1e18;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: WETH,
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Should return zero price when source price is invalid");
        assertEq(timestamp, 0, "Should return zero timestamp when source price is invalid");
    }

    function testDirectUsdConversion_StaleSourcePrice() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        MockChainlinkFeed staleFeed = new MockChainlinkFeed(1800e8, 8); // $1800 ETH/USD
        staleFeed.setUpdatedAt(block.timestamp - router.PRICE_STALENESS_THRESHOLD() - 1);

        chainlinkAdapter.addAsset(WETH, address(staleFeed), CHAINLINK_HEARTBEAT, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 sharePrice = 1e18;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: WETH,
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Should return zero price when source price is stale");
        assertEq(timestamp, 0, "Should return zero timestamp when source price is stale");
    }

    function testDirectUsdConversion_NonUsdPrices() public {
        vm.startPrank(admin);
        router.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        MockChainlinkFeed ethFeed = new MockChainlinkFeed(1e18, 18); // ETH/ETH price
        MockChainlinkFeed usdcFeed = new MockChainlinkFeed(1e18, 18); // USDC/ETH price

        chainlinkAdapter.addAsset(WETH, address(ethFeed), CHAINLINK_HEARTBEAT, false);
        chainlinkAdapter.addAsset(USDC, address(usdcFeed), CHAINLINK_HEARTBEAT, false);

        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        uint256 sharePrice = 1e18;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: WETH,
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Should return zero price when prices are not in USD");
        assertEq(timestamp, 0, "Should return zero timestamp when prices are not in USD");
    }

    function testGetCrossChainAssetPrice_LocalEquivalentPathway() public {
        // Setup
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address srcAsset = OPTIMISM_USDC;
        uint256 sharePrice = 1.5e6;

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        router.setCrossChainAssetMapping(srcChain, srcAsset, USDC);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: srcAsset,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertGt(price, 0, "Price should be non-zero");
        assertGt(timestamp, 0, "Timestamp should be non-zero");
    }

    function testGetCrossChainAssetPrice_DirectUsdConversion() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address srcAsset = OPTIMISM_USDC;
        uint256 sharePrice = 1.5e6;

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: srcAsset,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Price should be non-zero");
        assertEq(timestamp, 0, "Timestamp should be non-zero");
    }

    function testGetCrossChainAssetPrice_NoValidPrice() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address srcAsset = OPTIMISM_USDC;
        uint256 sharePrice = 1.5e6;

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: srcAsset,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, USDC);
        assertEq(price, 0, "Price should be zero when no valid conversion path exists");
        assertEq(timestamp, 0, "Timestamp should be zero when no valid conversion path exists");
    }

    function testDirectUsdConversion_InvalidDestinationPrice() public {
        uint32 srcChain = 10; // Optimism
        address vaultAddr = makeAddr("vault");
        address srcAsset = OPTIMISM_USDC;
        uint256 sharePrice = 1.5e6;

        vm.startPrank(admin);
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.addAdapter(address(chainlinkAdapter), 1);
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        chainlinkAdapter.addAsset(srcAsset, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: sharePrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: vaultAddr,
            asset: srcAsset,
            assetDecimals: 6
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(srcChain, vaultAddr, WETH);
        assertEq(price, 0, "Price should be zero with invalid destination price");
        assertEq(timestamp, 0, "Timestamp should be zero with invalid destination price");
    }
}
