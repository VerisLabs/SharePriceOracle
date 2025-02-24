// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SharePriceRouter} from "../../src/SharePriceRouter.sol";
import {ChainlinkAdapter} from "../../src/adapters/Chainlink.sol";
import {Api3Adaptor} from "../../src/adapters/Api3.sol";
import {IERC20Metadata} from "../../src/interfaces/IERC20Metadata.sol";
import {VaultReport} from "../../src/interfaces/ISharePriceOracle.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {MockVault} from "../mocks/MockVault.sol";

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

        console.log("=== Test Setup ===");
        console.log("Admin address:", admin);
        console.log("Updater address:", updater);
        console.log("Endpoint address:", endpoint);
        console.log("User address:", user);

        // Deploy router with admin as owner
        vm.prank(admin);
        router = new SharePriceRouter(admin, ETH_USD_FEED, USDC, WBTC, WETH);
        console.log("Router deployed at:", address(router));

        // Deploy adapters
        chainlinkAdapter = new ChainlinkAdapter(
            admin,
            address(router),
            address(router) // Router is now its own router
        );
        console.log(
            "Chainlink adapter deployed at:",
            address(chainlinkAdapter)
        );

        api3Adapter = new Api3Adaptor(
            admin,
            address(router),
            address(router), // Router is now its own router
            WETH
        );
        console.log("API3 adapter deployed at:", address(api3Adapter));

        // Deploy mock vaults with correct decimals for each asset
        // USDC: 6 decimals
        usdcVault = new MockVault(USDC, 6, 1.1e6); // 1.1 USDC
        // WETH: 18 decimals
        wethVault = new MockVault(WETH, 18, 1.1e18); // 1.1 ETH
        // WBTC: 8 decimals
        wbtcVault = new MockVault(WBTC, 8, 1.1e8); // 1.1 BTC
        // DAI: 18 decimals
        daiVault = new MockVault(DAI, 18, 1.1e18); // 1.1 DAI
        console.log("Mock vaults deployed");

        // Setup roles
        vm.startPrank(admin);
        console.log("Setting up roles as admin");
        router.grantRole(updater, router.UPDATER_ROLE());
        router.grantRole(endpoint, router.ENDPOINT_ROLE());
        vm.stopPrank();
        console.log("Roles setup completed");

        // Verify initial state
        console.log("Verifying initial state:");
        console.log(
            "Admin has ADMIN_ROLE:",
            router.hasAnyRole(admin, router.ADMIN_ROLE())
        );
        console.log(
            "Updater has UPDATER_ROLE:",
            router.hasAnyRole(updater, router.UPDATER_ROLE())
        );
        console.log(
            "Endpoint has ENDPOINT_ROLE:",
            router.hasAnyRole(endpoint, router.ENDPOINT_ROLE())
        );
    }

    // Admin function tests
    function testGrantRole() public {
        address newAdmin = makeAddr("newAdmin");

        console.log("Admin address:", admin);
        console.log("New admin address:", newAdmin);

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
        console.log("User address:", user);
        console.log("Current admin:", admin);

        vm.prank(user);
        console.log("Pranking as user to attempt setting asset category");
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
        console.log("\n=== Testing USDC Share Price ===");

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

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(usdcVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals
        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
        console.log("\n=== Testing DAI to USDC Share Price ===");

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
        console.log("Setting DAI vault share price to:", sharePrice);
        console.log("DAI decimals:", IERC20Metadata(DAI).decimals());
        console.log("USDC decimals:", IERC20Metadata(USDC).decimals());
        daiVault = new MockVault(DAI, 18, sharePrice);

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(daiVault), USDC);

        uint256 expectedSharePrice = 1.1e6; // 1.1 in USDC decimals
        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
        console.log(
            "\n=== Testing ETH to USDC Share Price (Cross Category) ==="
        );

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
        console.log("Current ETH/USD price:", ethPrice);
        console.log("Current USDC/USD price:", usdcPrice);

        // Create ETH vault with 1.1 ETH per share
        uint256 sharePrice = 1.1e18; // ETH uses 18 decimals
        console.log("Setting ETH vault share price to:", sharePrice);
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        console.log("WETH decimals:", wethDecimals);
        console.log("USDC decimals:", usdcDecimals);
        wethVault = new MockVault(WETH, 18, sharePrice);

        uint256 expectedSharePrice = (sharePrice * ethPrice) /
            (usdcPrice * 10 ** (wethDecimals - usdcDecimals));
        console.log(
            "Expected price (1.1 * ETH/USD in USDC decimals):",
            expectedSharePrice
        );

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(wethVault), USDC);

        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
        console.log(
            "\n=== Testing ETH to BTC Share Price (Cross Category) ==="
        );

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
        console.log("Setting ETH vault share price to:", sharePrice);
        uint8 wethDecimals = IERC20Metadata(WETH).decimals();
        uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
        console.log("WETH decimals:", wethDecimals);
        console.log("WBTC decimals:", wbtcDecimals);
        wethVault = new MockVault(WETH, 18, sharePrice);

        // Get current prices to calculate expected value
        (uint256 ethPrice, , ) = router.getLatestPrice(WETH, true);
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);

        // Calculate expected price: (1.1 * ETH/USD) / (BTC/USD) in BTC decimals
        uint256 expectedSharePrice = (sharePrice * ethPrice) /
            (btcPrice * 10 ** (wethDecimals - wbtcDecimals));
        console.log("Expected price:", expectedSharePrice);

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(wethVault), WBTC);

        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
        console.log(
            "\n=== Testing BTC to USDC Share Price (Cross Category) ==="
        );

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
        console.log("Setting BTC vault share price to:", sharePrice);
        uint8 btcDecimals = IERC20Metadata(WBTC).decimals();
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        console.log("WBTC decimals:", btcDecimals);
        console.log("USDC decimals:", usdcDecimals);
        wbtcVault = new MockVault(WBTC, 8, sharePrice);

        // Get current BTC/USD price to calculate expected value
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice, , ) = router.getLatestPrice(USDC, true);
        console.log("Current BTC/USD price:", btcPrice);
        console.log("Current USDC/USD price:", usdcPrice);

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(wbtcVault), USDC);

        uint256 expectedSharePrice = (sharePrice * btcPrice) /
            (usdcPrice * 10 ** (btcDecimals - usdcDecimals));
        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
        console.log(
            "\n=== Testing USDC to BTC Share Price (Cross Category) ==="
        );

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
        console.log("Setting USDC vault share price to:", sharePrice);
        uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
        uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
        console.log("USDC decimals:", usdcDecimals);
        console.log("WBTC decimals:", wbtcDecimals);
        usdcVault = new MockVault(USDC, 6, sharePrice);

        // Get current prices to calculate expected value
        (uint256 btcPrice, , ) = router.getLatestPrice(WBTC, true);
        (uint256 usdcPrice, , ) = router.getLatestPrice(USDC, true);
        console.log("Current BTC/USD price:", btcPrice);
        console.log("Current USDC/USD price:", usdcPrice);

        console.log("Getting share price from router...");
        (uint256 actualSharePrice, uint64 timestamp) = router
            .getLatestSharePrice(address(usdcVault), WBTC);

        (uint256 directConversion,) = router
            .convertStoredPrice(
                sharePrice, // 1.1e6
                USDC,
                WBTC
            );
        console.log("Direct convertStoredPrice result:", directConversion);

        uint256 shareUsdValue = (sharePrice * usdcPrice) / 1e6;
        uint256 expectedSharePrice = (shareUsdValue * 1e8) / btcPrice;
        console.log("Expected price:", expectedSharePrice);
        console.log("Actual price:", actualSharePrice);

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
}

