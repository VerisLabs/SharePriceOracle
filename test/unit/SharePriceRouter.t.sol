// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {SharePriceRouter} from "../../src/SharePriceRouter.sol";
import {ChainlinkAdapter} from "../../src/adapters/Chainlink.sol";
import {Api3Adaptor} from "../../src/adapters/Api3.sol";
import {IERC20Metadata} from "../../src/interfaces/IERC20Metadata.sol";
import {VaultReport} from "../../src/interfaces/ISharePriceRouter.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockVault} from "../mocks/MockVault.sol";
import {MockChainlinkSequencer} from "../mocks/MockChainlinkSequencer.sol";
import {IChainlink} from "../../src/interfaces/chainlink/IChainlink.sol";

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
uint256 constant CHAINLINK_HEARTBEAT = 86400; // 24 hours
uint256 constant API3_HEARTBEAT = 14400; // 4 hours

contract SharePriceRouterTest is Test {
    // Test contracts
    SharePriceRouter public router;
    ChainlinkAdapter public chainlinkAdapter;
    Api3Adaptor public api3Adapter;

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
        

        api3Adapter = new Api3Adaptor(
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

        assertTrue(
            router.hasAnyRole(newAdmin, router.ADMIN_ROLE()),
            "Role should be granted"
        );
    }

    function testRevokeRole() public {
        vm.startPrank(admin);
        router.grantRole(user, router.UPDATER_ROLE());
        router.revokeRole(user, router.UPDATER_ROLE());
        vm.stopPrank();

        assertFalse(
            router.hasAnyRole(user, router.UPDATER_ROLE()),
            "Role should be revoked"
        );
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

        assertEq(
            router.adapterPriorities(address(chainlinkAdapter)),
            1,
            "Adapter priority should be set"
        );
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

        assertEq(
            router.adapterPriorities(address(chainlinkAdapter)),
            0,
            "Adapter should be removed"
        );
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
        router.setAssetCategory(
            address(0),
            SharePriceRouter.AssetCategory.STABLE
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        vm.stopPrank();

        // Add price feed for USDC
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, 86400, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(usdcVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals

        // Allow for a small deviation (0.1%) in price
        uint256 maxDelta = expectedSharePrice / 1000; // 0.1% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current block"
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds for DAI and USDC
        chainlinkAdapter.addAsset(DAI, DAI_USD_FEED, 86400, true);
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, 86400, true);

        // Create DAI vault with 1.1 DAI per share
        uint256 sharePrice = 1.1e18; // DAI uses 18 decimals
        daiVault = new MockVault(DAI, 18, sharePrice);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(daiVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals

        // Allow for a small deviation (0.1%) in price due to conversion
        uint256 maxDelta = expectedSharePrice / 1000; // 0.1% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current"
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(
            WETH,
            ETH_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        chainlinkAdapter.addAsset(
            USDC,
            USDC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        api3Adapter.addAsset(
            WETH,
            "ETH/USD",
            API3_ETH_USD_FEED,
            API3_HEARTBEAT,
            true
        );

        // Get current ETH/USD price to calculate expected value
        (uint256 ethPrice, , ) = router.getLatestPrice(WETH, true);
        (uint256 usdcPrice, , ) = router.getLatestPrice(USDC, true);

        // Create ETH vault with 1.1 ETH per share
        uint256 sharePrice = 1.1e18; // ETH uses 18 decimals
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        
        wethVault = new MockVault(WETH, 18, sharePrice);

        uint256 expectedSharePrice = (sharePrice * ethPrice) /
            (usdcPrice * 10 ** (wethDecimals - usdcDecimals));

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(wethVault), USDC);

        // Allow for a small deviation (2%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = (expectedSharePrice * 2) / 100; // 2% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current"
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(
            WETH,
            ETH_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        chainlinkAdapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        api3Adapter.addAsset(
            WETH,
            "ETH/USD",
            API3_ETH_USD_FEED,
            API3_HEARTBEAT,
            true
        );
        api3Adapter.addAsset(
            WBTC,
            "WBTC/USD",
            API3_BTC_USD_FEED,
            API3_HEARTBEAT,
            true
        );

        // Create ETH vault with 1.1 ETH per share
        uint256 sharePrice = 1.1e18; // ETH uses 18 decimals
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
        wethVault = new MockVault(WETH, 18, sharePrice);

        // Get current prices to calculate expected value
        (uint256 ethPrice, , ) = router.getLatestPrice(WETH, true);
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);

        // Calculate expected price: (1.1 * ETH/USD) / (BTC/USD) in BTC decimals
        uint256 expectedSharePrice = (sharePrice * ethPrice) /
            (btcPrice * 10 ** (wethDecimals - wbtcDecimals));

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(wethVault), WBTC);

        // Allow for a larger deviation (1%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = expectedSharePrice / 100; // 1% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current"
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        chainlinkAdapter.addAsset(
            USDC,
            USDC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        api3Adapter.addAsset(
            WBTC,
            "WBTC/USD",
            API3_BTC_USD_FEED,
            API3_HEARTBEAT,
            true
        );

        // Create BTC vault with 1.1 BTC per share
        uint256 sharePrice = 1.1e8; // BTC uses 8 decimals
        uint8 btcDecimals = IERC20Metadata(WBTC).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        wbtcVault = new MockVault(WBTC, 8, sharePrice);

        // Get current BTC/USD price to calculate expected value
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice, , ) = router.getLatestPrice(USDC, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(wbtcVault), USDC);

        uint256 expectedSharePrice = (sharePrice * btcPrice) /
            (usdcPrice * 10 ** (btcDecimals - usdcDecimals));

        // Allow for a larger deviation (2%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = (expectedSharePrice * 2) / 100; // 2% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current"
        );
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
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ADMIN_ROLE()
        );
        chainlinkAdapter.grantRole(
            address(this),
            chainlinkAdapter.ORACLE_ROLE()
        );
        api3Adapter.grantRole(address(this), api3Adapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(this), api3Adapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feeds from multiple sources
        chainlinkAdapter.addAsset(
            USDC,
            USDC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        chainlinkAdapter.addAsset(
            WBTC,
            BTC_USD_FEED,
            CHAINLINK_HEARTBEAT,
            true
        );
        api3Adapter.addAsset(
            WBTC,
            "WBTC/USD",
            API3_BTC_USD_FEED,
            API3_HEARTBEAT,
            true
        );

        // Create USDC vault with 1.1 USDC per share
        uint256 sharePrice = 1.1e6; // USDC uses 6 decimals
        usdcVault = new MockVault(USDC, 6, sharePrice);

        // Get current prices to calculate expected value
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice, , ) = router.getLatestPrice(USDC, true);

        // Get latest share price
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(router.chainId(), address(usdcVault), WBTC);

        uint256 shareUsdValue = (sharePrice * usdcPrice) / 1e6;
        uint256 expectedSharePrice = (shareUsdValue * 1e8) / btcPrice;

        // Allow for a larger deviation (1%) due to cross-category conversion and multiple price sources
        uint256 maxDelta = expectedSharePrice / 100; // 1% of expected price
        assertApproxEqAbs(
            actualSharePrice,
            expectedSharePrice,
            maxDelta,
            "Share price should be close to expected value"
        );
        assertEq(
            timestamp,
            uint64(block.timestamp),
            "Timestamp should be current"
        );
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

    function testIsSequencerValid_NoSequencer() public {
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

        assertFalse(router.isSequencerValid(), "Should be invalid when sequencer is down");
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
        uint32 srcChain = 10;
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
        
        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);
        
        VaultReport memory stored = router.getLatestSharePriceReport(srcChain, vaultAddr);
        assertEq(stored.sharePrice, sharePrice, "Share price should be stored");
        assertEq(router.vaultChainIds(vaultAddr), srcChain, "Chain ID should be stored");
    }

    function testUpdateSharePrices_WithLocalEquivalent() public {
        uint32 srcChain = 10;
        address vaultAddr = makeAddr("vault");
        address srcAsset = makeAddr("srcAsset");
        address localAsset = USDC; // Using USDC as local equivalent
        uint256 sharePrice = 1e18;

        // Set up cross-chain mapping
        vm.prank(admin);
        router.setCrossChainAssetMapping(srcChain, srcAsset, localAsset);

        // Set up price feeds
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
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Verify stored share price
        VaultReport memory stored = router.getLatestSharePriceReport(srcChain, vaultAddr);
        assertEq(stored.sharePrice, sharePrice, "Share price should be stored");
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
        (uint256 initialPrice, , ) = router.getLatestPrice(USDC, true);
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
        uint32 srcChain = 10;
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

    function testCrossChainPriceConversion_WithMapping() public {
        address srcAsset = makeAddr("srcAsset");
        uint32 srcChain = 10;
        uint256 initialPrice = 1.5e18; // 1.5 units

        vm.startPrank(admin);
        // Set up USDC as local equivalent and set categories
        router.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);
        router.setAssetCategory(srcAsset, SharePriceRouter.AssetCategory.STABLE);
        router.setCrossChainAssetMapping(srcChain, srcAsset, USDC);
        router.addAdapter(address(chainlinkAdapter), 1);
        
        // Grant roles to chainlink adapter
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ADMIN_ROLE());
        chainlinkAdapter.grantRole(address(this), chainlinkAdapter.ORACLE_ROLE());
        vm.stopPrank();

        // Add price feed for USDC with proper heartbeat
        chainlinkAdapter.addAsset(USDC, USDC_USD_FEED, CHAINLINK_HEARTBEAT, true);

        // Update USDC price to ensure it's fresh
        vm.prank(updater);
        router.updatePrice(USDC, true);

        // Create and store a vault report
        VaultReport[] memory reports = new VaultReport[](1);
        reports[0] = VaultReport({
            sharePrice: initialPrice,
            lastUpdate: uint64(block.timestamp),
            chainId: srcChain,
            rewardsDelegate: address(0),
            vaultAddress: makeAddr("vault"),
            asset: srcAsset,
            assetDecimals: 18
        });

        vm.prank(endpoint);
        router.updateSharePrices(srcChain, reports);

        // Get latest share price in USDC
        (uint256 price, uint64 timestamp) = router.getLatestSharePrice(
            srcChain,
            reports[0].vaultAddress,
            USDC
        );

        assertTrue(price > 0, "Should get valid converted price");
        assertEq(timestamp, uint64(block.timestamp), "Timestamp should be current");

        // Since we're converting 1.5e18 (18 decimals) to USDC (6 decimals),
        // Expected: 1.5e18 * 1e6 / 1e18 = 1.5e6
        uint256 expectedPrice = 1.5e6; // 1.5 USDC
        uint256 tolerance = expectedPrice / 100; // 1% tolerance
        assertApproxEqAbs(price, expectedPrice, tolerance, "Price should be close to expected value");
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
        (uint256 price, uint256 timestamp, bool isUSD) = router.getLatestPrice(WETH, true);
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
        (uint256 initialPrice, , ) = router.getLatestPrice(WETH, true);
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
        (uint256 price, , bool isUSD) = router.getLatestPrice(WETH, true);
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
}

