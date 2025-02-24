// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/MaxLzEndpoint.sol";
import "../../src/SharePriceRouter.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE, USDCE_POLYGON, WETH_MAINNET } from "../utils/AddressBook.sol";
import { ChainlinkAdapter } from "../../src/adapters/Chainlink.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";

contract MaxLzEndpointTest is BaseTest {
    // Constants for BASE network
    address constant USDC = USDCE_BASE;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    
    MaxLzEndpoint public endpoint;
    SharePriceRouter public oracle;
    IERC4626 public vault;
    SharePriceRouter public oracle_pol;
    MaxLzEndpoint public endpoint_pol;

    address public admin;
    address public user;
    string[] public CHAINS = ["BASE", "POLYGON"];
    uint256[] public FORK_BLOCKS = [24_666_153, 65_990_633];

    event MessageProcessed(bytes32 indexed guid, bytes message);
    event PeerSet(uint32 indexed eid, bytes32 peer);
    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event VaultAddressesSent(uint32 indexed dstEid, address[] vaults);
    event SharePricesRequested(uint32 indexed dstEid, address[] vaults);
    event EnforcedOptionsSet(MaxLzEndpoint.EnforcedOptionParam[] params);
    event SharePriceUpdated(uint32 indexed chainId, address indexed vault, uint256 sharePrice, address rewardsDelegate);
    event RoleRevoked(address indexed account, bytes32 indexed role);
    event RoleGranted(address indexed account, bytes32 indexed role);
    event ETHWithdrawn(address indexed recipient, uint256 amount);
    event SharePricesSent(uint32 indexed dstEid, address[] vaults);

    address public constant base_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant polygon_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;

    // Chainlink price feed addresses on BASE
    address constant BASE_ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant BASE_BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;
    
    // Chainlink price feed addresses on POLYGON
    address constant POLYGON_ETH_USD_FEED = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address constant POLYGON_BTC_USD_FEED = 0xc907E116054Ad103354f2D350FD2514433D57F6f;
    
    // Heartbeat values
    uint256 constant ETH_HEARTBEAT = 1200;  // 20 minutes
    uint256 constant BTC_HEARTBEAT = 1200;  // 20 minutes

    function setUp() public {
        _setUp(CHAINS, FORK_BLOCKS);

        admin = makeAddr("admin");
        user = makeAddr("user");

        // Mock Chainlink price feeds for BASE
        vm.mockCall(
            BASE_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );
        vm.mockCall(
            BASE_BTC_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(50000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );

        vm.startPrank(admin);
        switchTo("BASE");
        vm.chainId(8453);
        oracle = new SharePriceRouter(admin, BASE_ETH_USD_FEED, USDC, WBTC, WETH);
        endpoint = new MaxLzEndpoint(admin, 0x1a44076050125825900e736c501f859c50fE728c, address(oracle));

        // Deploy and set up Chainlink adapter for BASE
        ChainlinkAdapter baseAdapter = new ChainlinkAdapter(
            admin,
            address(oracle),
            address(oracle)
        );
        oracle.addAdapter(address(baseAdapter), 1);
        baseAdapter.grantRole(admin, uint256(baseAdapter.ORACLE_ROLE()));
        baseAdapter.addAsset(WETH, BASE_ETH_USD_FEED, ETH_HEARTBEAT, true);
        baseAdapter.addAsset(WBTC, BASE_BTC_USD_FEED, BTC_HEARTBEAT, true);

        // Set asset categories for BASE oracle
        oracle.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        oracle.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);
        oracle.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());
        vault = IERC4626(0xA70b9595bad8EdbEfa9F416ee36061b1fA8d1160);

        // Mock vault functions
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.asset.selector),
            abi.encode(WETH)
        );
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC4626.convertToAssets.selector, 1e18),
            abi.encode(1e18)  // 1:1 ratio for simplicity
        );
        vm.mockCall(
            address(vault),
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(18)
        );

        // Mock token decimals for BASE
        vm.mockCall(
            WETH,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(18)
        );
        vm.mockCall(
            WBTC,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(8)
        );
        vm.mockCall(
            USDC,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(6)
        );

        // Mock USD price feed for BASE
        vm.mockCall(
            BASE_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );

        vm.makePersistent(address(vault));
        vm.stopPrank();

        // Mock Chainlink price feeds for Polygon
        vm.mockCall(
            POLYGON_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );
        vm.mockCall(
            POLYGON_BTC_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(50000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );

        // Mock token decimals for POLYGON
        vm.mockCall(
            WETH,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(18)
        );
        vm.mockCall(
            WBTC,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(8)
        );
        vm.mockCall(
            USDC,
            abi.encodeWithSelector(IERC20Metadata.decimals.selector),
            abi.encode(6)
        );

        // Mock USD price feed for POLYGON
        vm.mockCall(
            POLYGON_ETH_USD_FEED,
            abi.encodeWithSelector(IChainlink.latestRoundData.selector),
            abi.encode(uint80(1), int256(2000e8), uint256(block.timestamp), uint256(block.timestamp), uint80(1))
        );

        vm.startPrank(admin);
        switchTo("POLYGON");
        vm.chainId(137);
        oracle_pol = new SharePriceRouter(admin, POLYGON_ETH_USD_FEED, USDC, WBTC, WETH);
        endpoint_pol = new MaxLzEndpoint(admin, 0x1a44076050125825900e736c501f859c50fE728c, address(oracle_pol));

        // Deploy and set up Chainlink adapter for POLYGON
        ChainlinkAdapter polygonAdapter = new ChainlinkAdapter(
            admin,
            address(oracle_pol),
            address(oracle_pol)
        );
        oracle_pol.addAdapter(address(polygonAdapter), 1);
        polygonAdapter.grantRole(admin, uint256(polygonAdapter.ORACLE_ROLE()));
        polygonAdapter.addAsset(WETH, POLYGON_ETH_USD_FEED, ETH_HEARTBEAT, true);
        polygonAdapter.addAsset(WBTC, POLYGON_BTC_USD_FEED, BTC_HEARTBEAT, true);

        // Set asset categories for POLYGON oracle
        oracle_pol.setAssetCategory(WETH, SharePriceRouter.AssetCategory.ETH_LIKE);
        oracle_pol.setAssetCategory(WBTC, SharePriceRouter.AssetCategory.BTC_LIKE);
        oracle_pol.setAssetCategory(USDC, SharePriceRouter.AssetCategory.STABLE);

        vm.stopPrank();

        switchTo("BASE");

        vm.startPrank(admin);
        endpoint.setPeer(30_109, bytes32(uint256(uint160(address(endpoint_pol)))));
        endpoint.setPeer(30_184, bytes32(uint256(uint160(address(endpoint)))));
        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());
        vm.stopPrank();

        switchTo("POLYGON");
        vm.startPrank(admin);
        endpoint_pol.setPeer(30_184, bytes32(uint256(uint160(address(endpoint)))));

        oracle_pol.grantRole(address(endpoint_pol), oracle_pol.ENDPOINT_ROLE());

        endpoint_pol.setPeer(30_109, bytes32(uint256(uint160(address(endpoint_pol)))));
        vm.stopPrank();

        vm.deal(admin, 1000 ether);
        vm.deal(user, 1000 ether);
    }

    function test_constructor() public {
        switchTo("BASE");
        MaxLzEndpoint newEndpoint = new MaxLzEndpoint(admin, base_LZ_end, address(oracle));

        assertEq(address(newEndpoint.oracle()), address(oracle));
        assertEq(address(newEndpoint.endpoint()), base_LZ_end);
        assertTrue(newEndpoint.owner() == admin);
    }

    function test_revertWhen_ConstructorWithZeroAdmin() public {
        switchTo("BASE");
        vm.expectRevert();
        new MaxLzEndpoint(address(0), base_LZ_end, address(oracle));
    }

    function test_revertWhen_ConstructorWithZeroOracle() public {
        switchTo("BASE");
        vm.expectRevert();
        new MaxLzEndpoint(admin, base_LZ_end, address(0));
    }

    function test_setPeer() public {
        switchTo("BASE");
        vm.startPrank(admin);

        bytes32 newPeer = bytes32(uint256(uint160(makeAddr("newPeer"))));
        vm.expectEmit(true, true, true, true);
        emit PeerSet(30_109, newPeer);

        endpoint.setPeer(30_109, newPeer);
        assertEq(endpoint.peers(30_109), newPeer);
        vm.stopPrank();
    }

    function test_revertWhen_SetPeerCalledByNonOwner() public {
        switchTo("BASE");
        vm.prank(user);
        vm.expectRevert();
        endpoint.setPeer(30_109, bytes32(0));
    }

    function test_revertWhen_SetPeerWithInvalidPeer() public {
        switchTo("BASE");
        vm.prank(admin);
        vm.expectRevert();
        endpoint.setPeer(30_109, bytes32(0));
    }

    function test_revertWhen_SendSharePricesWithInsufficientFee() public {
        switchTo("BASE");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        vm.expectRevert();
        endpoint.sendSharePrices{ value: 0 }(30_109, vaults, options, user);
        vm.stopPrank();
    }

    function test_requestSharePrices_singleVault() public {
        switchTo("POLYGON");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        bytes memory returnOptions = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        uint256 fee = endpoint_pol.estimateFees(30_109, 2, abi.encode(2, vaults, user), options);

        vm.expectEmit(true, true, true, true);
        emit SharePricesRequested(30_109, vaults);

        endpoint_pol.requestSharePrices{ value: fee * 2 }(30_109, vaults, options, returnOptions, user);
        vm.stopPrank();
    }

    function test_revertWhen_RequestSharePricesWithInsufficientFee() public {
        switchTo("POLYGON");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        bytes memory returnOptions = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        vm.expectRevert();
        endpoint_pol.requestSharePrices{ value: 0 }(30_109, vaults, options, returnOptions, user);
        vm.stopPrank();
    }

    function test_estimateFees() public {
        switchTo("BASE");

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        uint256 fee = endpoint.estimateFees(30_109, 1, abi.encode(1, vaults, user), options);
        assertGt(fee, 0);
    }

    function test_sendSharePrices_BaseToPolygon() public {
        switchTo("BASE");

        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        uint256 fee = endpoint.estimateFees(30_109, 1, abi.encode(1, vaults, user), options);
        vm.expectEmit(true, true, true, true);
        emit SharePricesSent(30_109, vaults);
        deal(user, 1000 ether);
        endpoint.sendSharePrices{ value: fee * 2 }(30_109, vaults, options, user);

        VaultReport[] memory reports = oracle.getSharePrices(vaults, user);

        switchTo("POLYGON");

        vm.startPrank(polygon_LZ_end);

        Origin memory origin = Origin(30_184, bytes32(uint256(uint160(address(endpoint)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        bytes memory message = MsgCodec.encodeVaultReports(1, reports, options);

        endpoint_pol.lzReceive(origin, guid, message, address(0), bytes(""));

        VaultReport memory report = oracle_pol.getLatestSharePriceReport(8453, address(vault));

        assertEq(report.vaultAddress, report.vaultAddress);
        assertEq(report.chainId, 8453);
        assertEq(report.rewardsDelegate, user);

        vm.stopPrank();
    }

    function test_requestSharePrices_BaseToPolygon() public {
        switchTo("POLYGON");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        bytes memory returnOptions = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        uint256 fee = endpoint_pol.estimateFees(30_109, 2, abi.encode(2, vaults, user), options);
        deal(address(endpoint_pol), 1000 ether);
        deal(polygon_LZ_end, 1000 ether);
        deal(user, 1000 ether);
        endpoint_pol.requestSharePrices{ value: fee * 2 }(30_109, vaults, options, returnOptions, user);

        switchTo("BASE");

        vm.startPrank(base_LZ_end);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        bytes memory message = MsgCodec.encodeVaultAddresses(2, vaults, user, returnOptions);
        deal(address(endpoint), 1000 ether);
        deal(base_LZ_end, 1000 ether);

        endpoint_pol.lzReceive(origin, guid, message, address(0), bytes(""));
        VaultReport[] memory reports = oracle.getSharePrices(vaults, user);

        switchTo("POLYGON");

        vm.startPrank(polygon_LZ_end);

        Origin memory origin2 = Origin(30_184, bytes32(uint256(uint160(address(endpoint)))), 0);
        bytes32 guid2 = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        bytes memory message2 = MsgCodec.encodeVaultReports(1, reports, options);

        endpoint_pol.lzReceive(origin2, guid2, message2, address(0), bytes(""));

        VaultReport memory report = oracle_pol.getLatestSharePriceReport(8453, address(vault));

        assertEq(report.vaultAddress, report.vaultAddress);
        assertEq(report.chainId, 8453);
        assertEq(report.rewardsDelegate, user);

        vm.stopPrank();
    }

    function test_revertWhen_LzReceiveWithInvalidEndpoint() public {
        switchTo("BASE");
        vm.prank(user);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        vm.expectRevert();
        endpoint.lzReceive(origin, guid, "", address(0), bytes(""));
    }

    function test_revertWhen_LzReceiveWithInvalidPeer() public {
        switchTo("BASE");
        vm.prank(base_LZ_end);

        Origin memory origin = Origin(30_109, bytes32(0), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        vm.expectRevert();
        endpoint.lzReceive(origin, guid, "", address(0), bytes(""));
    }

    function test_revertWhen_LzReceiveWithDuplicateMessage() public {
        switchTo("BASE");
        vm.startPrank(base_LZ_end);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);
        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        bytes memory message = MsgCodec.encodeVaultAddresses(2, vaults, user, options);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        deal(address(endpoint), 1000 ether);
        deal(base_LZ_end, 1000 ether);
        deal(polygon_LZ_end, 1000 ether);

        endpoint.lzReceive(origin, guid, message, address(0), bytes(""));

        vm.expectRevert();
        endpoint.lzReceive(origin, guid, message, address(0), bytes(""));

        vm.stopPrank();
    }

    function test_revertWhen_SetLzEndpointByNonOwner() public {
        switchTo("BASE");
        vm.prank(user);
        vm.expectRevert();
        endpoint.setLzEndpoint(makeAddr("newEndpoint"));
    }

    function test_revertWhen_SetLzEndpointWithZeroAddress() public {
        switchTo("BASE");
        vm.prank(admin);
        vm.expectRevert();
        endpoint.setLzEndpoint(address(0));
    }

    function test_revertWhen_SetLzEndpointWhenEndpointExists() public {
        switchTo("BASE");
        vm.startPrank(admin);

        vm.expectRevert();
        endpoint.setLzEndpoint(makeAddr("newEndpoint"));

        vm.stopPrank();
    }

    function test_revertWhen_WithdrawETHByNonOwner() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(user);
        vm.expectRevert();
        endpoint.refundETH(1 ether, user);
    }

    function test_revertWhen_WithdrawETHToZeroAddress() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        vm.expectRevert();
        endpoint.refundETH(1 ether, address(0));
    }

    function test_revertWhen_WithdrawETHZeroAmount() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        vm.expectRevert();
        endpoint.refundETH(0, user);
    }

    function test_revertWhen_WithdrawETHInsufficientBalance() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        vm.expectRevert();
        endpoint.refundETH(2 ether, user);
    }
}