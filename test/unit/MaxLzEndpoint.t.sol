// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/MaxLzEndpoint.sol";
import "../../src/SharePriceOracle.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";
import { USDCE_BASE, USDCE_POLYGON, WETH_MAINNET } from "../utils/AddressBook.sol";
import { ChainlinkAdapter } from "../../src/adapters/Chainlink.sol";
import { IChainlink } from "../../src/interfaces/chainlink/IChainlink.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";
import { ILayerZeroEndpointV2 } from "../../src/interfaces/ILayerZeroEndpointV2.sol";

contract MaxLzEndpointTest is BaseTest {
    // Constants for BASE network
    address constant USDC = USDCE_BASE;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;

    MaxLzEndpoint public endpoint;
    SharePriceOracle public oracle;
    IERC4626 public vault;
    SharePriceOracle public oracle_pol;
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
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);

    address public constant base_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant polygon_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;
    // The LayerZero endpoint contracts that need to be made persistent
    address public constant lz_endpoint_contract = 0x6c26c61a97006888ea9E4FA36584c7df57Cd9dA3;
    address public constant lz_dvn_contract1 = 0x23DE2FE932d9043291f870324B74F820e11dc81A;
    address public constant lz_dvn_contract2 = 0xD56e4eAb23cb81f43168F9F45211Eb027b9aC7cc;
    address public constant lz_executor_contract = 0xCd3F213AD101472e1713C72B1697E727C803885b;
    address public constant lz_treasury_contract = 0xECEE8B581960634aF89f467AE624Ff468a9Db14B;
    address public constant lz_fee_lib_contract = 0x6A6991E0bF27E3CcCDe6B73dE94b7DA6e240FF6E;
    address public constant lz_price_feed = 0x119C04C4E60158fa69eCf4cdDF629D09719a7572;
    address public constant lz_price_feed_impl = 0x986B05a8d540bE18c3352Fb50Ff714333f5dCE38;
    address public constant lz_executor_lib = 0x31F8e74923A738fA489df178E2088885CEb54A9d;
    address public constant lz_executor_impl = 0x2022D5A3eb01039140F1338504a6dBA0EC2179b8;

    // Chainlink price feed addresses on BASE
    address constant BASE_ETH_USD_FEED = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;
    address constant BASE_BTC_USD_FEED = 0xCCADC697c55bbB68dc5bCdf8d3CBe83CdD4E071E;

    // Chainlink price feed addresses on POLYGON
    address constant POLYGON_ETH_USD_FEED = 0xF9680D99D6C9589e2a93a78A04A279e509205945;
    address constant POLYGON_BTC_USD_FEED = 0xc907E116054Ad103354f2D350FD2514433D57F6f;

    // Heartbeat values
    uint256 constant ETH_HEARTBEAT = 1200; // 20 minutes
    uint256 constant BTC_HEARTBEAT = 1200; // 20 minutes

    function setUp() public {
        _setUp(CHAINS, FORK_BLOCKS);

        admin = makeAddr("admin");
        user = makeAddr("user");

        // Make the LZ endpoints persistent
        vm.makePersistent(base_LZ_end);
        vm.makePersistent(polygon_LZ_end);
        // Make the LayerZero endpoint contracts persistent
        vm.makePersistent(lz_endpoint_contract);
        vm.makePersistent(lz_dvn_contract1);
        vm.makePersistent(lz_dvn_contract2);
        vm.makePersistent(lz_executor_contract);
        vm.makePersistent(lz_treasury_contract);
        vm.makePersistent(lz_fee_lib_contract);
        vm.makePersistent(lz_price_feed);
        vm.makePersistent(lz_price_feed_impl);
        vm.makePersistent(lz_executor_lib);
        vm.makePersistent(lz_executor_impl);

        vm.startPrank(admin);

        // Setup BASE chain
        switchTo("BASE");
        vm.chainId(8453);

        // Deploy BASE contracts
        oracle = new SharePriceOracle(admin);
        endpoint = new MaxLzEndpoint(admin, base_LZ_end, address(oracle));

        // Setup Chainlink adapter for BASE
        ChainlinkAdapter baseAdapter = new ChainlinkAdapter(admin, address(oracle), address(oracle));

        // Configure price feeds in router
        oracle.setLocalAssetConfig(WETH, address(baseAdapter), BASE_ETH_USD_FEED, 0, true);
        oracle.setLocalAssetConfig(WBTC, address(baseAdapter), BASE_BTC_USD_FEED, 0, true);

        // Setup adapter
        baseAdapter.grantRole(admin, uint256(baseAdapter.ORACLE_ROLE()));
        baseAdapter.addAsset(WETH, BASE_ETH_USD_FEED, ETH_HEARTBEAT, true);
        baseAdapter.addAsset(WBTC, BASE_BTC_USD_FEED, BTC_HEARTBEAT, true);

        // Grant endpoint role
        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());

        // Mock only the necessary vault functions
        vault = IERC4626(0xA70b9595bad8EdbEfa9F416ee36061b1fA8d1160);
        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.asset.selector), abi.encode(WETH));
        vm.mockCall(address(vault), abi.encodeWithSelector(IERC4626.convertToAssets.selector, 1e18), abi.encode(1e18));
        vm.makePersistent(address(vault));

        // Setup POLYGON chain
        switchTo("POLYGON");
        vm.chainId(137);

        // Deploy POLYGON contracts
        oracle_pol = new SharePriceOracle(admin);
        endpoint_pol = new MaxLzEndpoint(admin, polygon_LZ_end, address(oracle_pol));

        // Setup Chainlink adapter for POLYGON
        ChainlinkAdapter polygonAdapter = new ChainlinkAdapter(admin, address(oracle_pol), address(oracle_pol));

        // Configure price feeds in router
        oracle_pol.setLocalAssetConfig(WETH, address(polygonAdapter), POLYGON_ETH_USD_FEED, 0, true);
        oracle_pol.setLocalAssetConfig(WBTC, address(polygonAdapter), POLYGON_BTC_USD_FEED, 0, true);

        // Setup adapter
        polygonAdapter.grantRole(admin, uint256(polygonAdapter.ORACLE_ROLE()));
        polygonAdapter.addAsset(WETH, POLYGON_ETH_USD_FEED, ETH_HEARTBEAT, true);
        polygonAdapter.addAsset(WBTC, POLYGON_BTC_USD_FEED, BTC_HEARTBEAT, true);

        // Grant endpoint role
        oracle_pol.grantRole(address(endpoint_pol), oracle_pol.ENDPOINT_ROLE());

        // Setup cross-chain communication - IMPORTANT: Order matters here
        // First set up BASE endpoint peers
        switchTo("BASE");
        endpoint.setPeer(30_109, bytes32(uint256(uint160(address(endpoint_pol)))));
        endpoint.setPeer(30_184, bytes32(uint256(uint160(address(endpoint)))));

        // Set up cross-chain asset mappings for BASE
        oracle.setCrossChainAssetMapping(137, USDCE_POLYGON, USDC);
        oracle.setCrossChainAssetMapping(137, WETH, WETH);
        oracle.setCrossChainAssetMapping(137, WBTC, WBTC);

        // Then set up POLYGON endpoint peers
        switchTo("POLYGON");
        endpoint_pol.setPeer(30_184, bytes32(uint256(uint160(address(endpoint)))));
        endpoint_pol.setPeer(30_109, bytes32(uint256(uint160(address(endpoint_pol)))));

        // Set up cross-chain asset mappings for POLYGON
        oracle_pol.setCrossChainAssetMapping(8453, USDC, USDCE_POLYGON);
        oracle_pol.setCrossChainAssetMapping(8453, WETH, WETH);
        oracle_pol.setCrossChainAssetMapping(8453, WBTC, WBTC);

        vm.stopPrank();

        // Fund test accounts
        vm.deal(admin, 1000 ether);
        vm.deal(user, 1000 ether);

        // Switch back to BASE for the start of tests
        switchTo("BASE");
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

        uint256 mockFee = 15_780_837_555_745;
        vm.mockCall(
            base_LZ_end,
            abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
            abi.encode(MessagingFee(mockFee, 0))
        );

        vm.deal(user, mockFee);

        vm.expectEmit(true, true, true, true);
        emit SharePricesSent(30_109, vaults);

        endpoint.sendSharePrices{ value: mockFee }(30_109, vaults, options, user);

        vm.stopPrank();
    }

    function test_requestSharePrices_BaseToPolygon() public {
        switchTo("BASE");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        bytes memory receiveOptions = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

        uint256 mockFee = 323_952_032_069_472_984;
        vm.mockCall(
            base_LZ_end,
            abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
            abi.encode(MessagingFee(mockFee, 0))
        );

        vm.deal(user, mockFee);

        vm.expectEmit(true, true, true, true);
        emit SharePricesRequested(30_109, vaults);

        endpoint.requestSharePrices{ value: mockFee }(30_109, vaults, options, receiveOptions, user);

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

    function test_setEnforcedOptions() public {
        switchTo("BASE");
        vm.startPrank(admin);

        MaxLzEndpoint.EnforcedOptionParam[] memory params = new MaxLzEndpoint.EnforcedOptionParam[](1);
        params[0] = MaxLzEndpoint.EnforcedOptionParam({
            eid: 30_109,
            msgType: 1,
            options: endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0)
        });

        vm.expectEmit(true, true, true, true);
        emit EnforcedOptionsSet(params);

        endpoint.setEnforcedOptions(params);

        bytes memory storedOptions = endpoint.enforcedOptions(30_109, 1);
        assertEq(storedOptions, params[0].options, "Enforced options should be stored");

        vm.stopPrank();
    }

    function test_revertWhen_SetEnforcedOptionsWithInvalidType() public {
        switchTo("BASE");
        vm.startPrank(admin);

        MaxLzEndpoint.EnforcedOptionParam[] memory params = new MaxLzEndpoint.EnforcedOptionParam[](1);
        params[0] = MaxLzEndpoint.EnforcedOptionParam({ eid: 30_109, msgType: 1, options: hex"0001" });

        vm.expectRevert();
        endpoint.setEnforcedOptions(params);

        vm.stopPrank();
    }

    function test_setOracle() public {
        switchTo("BASE");
        vm.startPrank(admin);

        address newOracle = makeAddr("newOracle");
        vm.expectEmit(true, true, true, true);
        emit OracleUpdated(address(oracle), newOracle);

        endpoint.setOracle(newOracle);
        assertEq(address(endpoint.oracle()), newOracle, "Oracle should be updated");

        vm.stopPrank();
    }

    function test_revertWhen_SetOracleWithZeroAddress() public {
        switchTo("BASE");
        vm.prank(admin);
        vm.expectRevert();
        endpoint.setOracle(address(0));
    }

    function test_revertWhen_SetOracleByNonOwner() public {
        switchTo("BASE");
        vm.prank(user);
        vm.expectRevert();
        endpoint.setOracle(makeAddr("newOracle"));
    }

    function test_refundETH() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 2 ether);

        uint256 initialBalance = user.balance;
        uint256 refundAmount = 1 ether;

        vm.prank(admin);
        endpoint.refundETH(refundAmount, user);

        assertEq(user.balance, initialBalance + refundAmount, "ETH should be refunded");
        assertEq(address(endpoint).balance, 1 ether, "Contract balance should be reduced");
    }

    function test_assertOptionsType3() public {
        switchTo("BASE");
        vm.startPrank(admin);

        bytes memory validOptions = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        MaxLzEndpoint.EnforcedOptionParam[] memory params = new MaxLzEndpoint.EnforcedOptionParam[](1);
        params[0] = MaxLzEndpoint.EnforcedOptionParam({ eid: 30_109, msgType: 1, options: validOptions });

        endpoint.setEnforcedOptions(params);

        bytes memory invalidOptions = hex"0002";
        params[0].options = invalidOptions;

        vm.expectRevert();
        endpoint.setEnforcedOptions(params);

        bytes memory tooShortOptions = hex"00";
        params[0].options = tooShortOptions;

        vm.expectRevert();
        endpoint.setEnforcedOptions(params);

        vm.stopPrank();
    }

    function test_revertWhen_InvalidOptionsLength() public {
        switchTo("BASE");
        vm.startPrank(admin);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory invalidOptions = hex"00";

        uint256 mockFee = 15_780_837_555_745;
        vm.mockCall(
            base_LZ_end,
            abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
            abi.encode(MessagingFee(mockFee, 0))
        );

        vm.deal(admin, mockFee);

        vm.expectRevert();
        endpoint.sendSharePrices{ value: mockFee }(30_109, vaults, invalidOptions, user);

        vm.stopPrank();
    }

    function test_allowInitializePath() public {
        switchTo("BASE");

        Origin memory validOrigin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bool allowed = endpoint.allowInitializePath(validOrigin);
        assertTrue(allowed, "Should allow initialization from valid peer");

        Origin memory invalidOrigin = Origin(30_109, bytes32(uint256(uint160(makeAddr("not-a-peer")))), 0);
        allowed = endpoint.allowInitializePath(invalidOrigin);
        assertFalse(allowed, "Should not allow initialization from invalid peer");
    }

    function test_nextNonce() public {
        switchTo("BASE");

        uint64 nonce = endpoint.nextNonce(0, bytes32(0));
        assertEq(nonce, 0, "Next nonce should always be 0");
    }

    function test_newOptions_and_addExecutorLzReceiveOption() public {
        switchTo("BASE");

        bytes memory options = endpoint.newOptions();
        assertEq(options.length, 2, "New options should have length 2");
        assertEq(options[0], 0x00, "First byte of new options should be 0x00");

        bytes memory optionsWithExecutor = endpoint.addExecutorLzReceiveOption(options, 200_000, 0);
        assertGt(optionsWithExecutor.length, options.length, "Options with executor should be longer");

        bytes memory optionsWithValue = endpoint.addExecutorLzReceiveOption(options, 200_000, 100);
        assertGt(optionsWithValue.length, optionsWithExecutor.length, "Options with value should be longer");
    }

    function test_receive_function() public {
        switchTo("BASE");

        uint256 initialBalance = address(endpoint).balance;

        (bool success,) = address(endpoint).call{ value: 1 ether }("");
        assertTrue(success, "Receive function should accept ETH");

        assertEq(address(endpoint).balance, initialBalance + 1 ether, "Contract balance should increase");
    }

    function test_revertWhen_ABAResponseWithInsufficientFunds() public {
        switchTo("BASE");
        vm.startPrank(base_LZ_end);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory returnOptions = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        bytes memory message = MsgCodec.encodeVaultAddresses(2, vaults, user, returnOptions);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        ISharePriceOracle.VaultReport[] memory reports = new ISharePriceOracle.VaultReport[](1);
        reports[0] = ISharePriceOracle.VaultReport({
            chainId: 8453,
            vaultAddress: address(vault),
            sharePrice: 1e18,
            rewardsDelegate: user,
            lastUpdate: uint64(block.timestamp),
            asset: WETH,
            assetDecimals: 18
        });

        vm.mockCall(
            address(oracle), abi.encodeWithSelector(ISharePriceOracle.getSharePrices.selector), abi.encode(reports)
        );

        vm.mockCall(
            base_LZ_end,
            abi.encodeWithSelector(ILayerZeroEndpointV2.quote.selector),
            abi.encode(MessagingFee(1 ether, 0))
        );

        vm.expectRevert();
        endpoint.lzReceive(origin, guid, message, address(0), "");

        vm.stopPrank();
    }
}
