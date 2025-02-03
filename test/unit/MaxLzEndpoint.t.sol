// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import "../../src/MaxLzEndpoint.sol";
import "../../src/SharePriceOracle.sol";
import "../helpers/Tokens.sol";
import "../base/BaseTest.t.sol";

contract MaxLzEndpointTest is BaseTest {
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

    address public constant base_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant polygon_LZ_end = 0x1a44076050125825900e736c501f859c50fE728c;

    function setUp() public {
        _setUp(CHAINS, FORK_BLOCKS);

        admin = makeAddr("admin");
        user = makeAddr("user");

        vm.startPrank(admin);
        switchTo("BASE");
        vm.chainId(8453);
        oracle = new SharePriceOracle(admin, 0xEE64Cd853b0830EEce4E957F24BCD89e587577E3);
        endpoint = new MaxLzEndpoint(admin, 0x1a44076050125825900e736c501f859c50fE728c, address(oracle));

        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());
        vault = IERC4626(0xA70b9595bad8EdbEfa9F416ee36061b1fA8d1160);
        vm.makePersistent(address(vault));
        vm.stopPrank();

        vm.startPrank(admin);
        switchTo("POLYGON");
        vm.chainId(137);
        oracle_pol = new SharePriceOracle(admin, 0xC9D4C66E07Ec5a7Da1C06e53359571a5f0089354);
        endpoint_pol = new MaxLzEndpoint(admin, 0x1a44076050125825900e736c501f859c50fE728c, address(oracle_pol));

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

    function testFail_constructor_zeroAdmin() public {
        switchTo("BASE");
        new MaxLzEndpoint(address(0), base_LZ_end, address(oracle));
    }

    function testFail_constructor_zeroOracle() public {
        switchTo("BASE");
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

    function testFail_setPeer_notOwner() public {
        switchTo("BASE");
        vm.prank(user);
        endpoint.setPeer(30_109, bytes32(0));
    }

    function testFail_setPeer_invalidPeer() public {
        switchTo("BASE");
        vm.prank(admin);
        endpoint.setPeer(30_109, bytes32(0));
    }

    function testFail_sendSharePrices_insufficientFee() public {
        switchTo("BASE");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

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

    function testFail_requestSharePrices_insufficientFee() public {
        switchTo("POLYGON");
        vm.startPrank(user);

        address[] memory vaults = new address[](1);
        vaults[0] = address(vault);

        bytes memory options = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);
        bytes memory returnOptions = endpoint_pol.addExecutorLzReceiveOption(endpoint.newOptions(), 200_000, 0);

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

    function testFail_lzReceive_invalidEndpoint() public {
        switchTo("BASE");
        vm.prank(user);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        endpoint.lzReceive(origin, guid, "", address(0), bytes(""));
    }

    function testFail_lzReceive_invalidPeer() public {
        switchTo("BASE");
        vm.prank(base_LZ_end);

        Origin memory origin = Origin(30_109, bytes32(0), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));

        endpoint.lzReceive(origin, guid, "", address(0), bytes(""));
    }

    function testFail_lzReceive_duplicateMessage() public {
        switchTo("BASE");
        vm.startPrank(base_LZ_end);

        Origin memory origin = Origin(30_109, bytes32(uint256(uint160(address(endpoint_pol)))), 0);
        bytes32 guid = keccak256(abi.encodePacked(block.timestamp, msg.sender));
        bytes memory message = "";

        endpoint.lzReceive(origin, guid, message, address(0), bytes(""));
        endpoint.lzReceive(origin, guid, message, address(0), bytes(""));

        vm.stopPrank();
    }

    function testFail_setLzEndpoint_notOwner() public {
        switchTo("BASE");
        vm.prank(user);
        endpoint.setLzEndpoint(makeAddr("newEndpoint"));
    }

    function testFail_setLzEndpoint_zeroAddress() public {
        switchTo("BASE");
        vm.prank(admin);
        endpoint.setLzEndpoint(address(0));
    }

    function testFail_setLzEndpoint_endpointExists() public {
        switchTo("BASE");
        vm.startPrank(admin);

        address newEndpoint = makeAddr("newEndpoint");
        endpoint.setLzEndpoint(newEndpoint);

        endpoint.setLzEndpoint(makeAddr("anotherEndpoint"));
        vm.stopPrank();
    }

    function testFail_withdrawETH_notOwner() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(user);
        endpoint.refundETH(1 ether, user);
    }

    function testFail_withdrawETH_zeroAddress() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        endpoint.refundETH(1 ether, address(0));
    }

    function testFail_withdrawETH_zeroAmount() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        endpoint.refundETH(0, user);
    }

    function testFail_withdrawETH_insufficientBalance() public {
        switchTo("BASE");
        vm.deal(address(endpoint), 1 ether);

        vm.prank(admin);
        endpoint.refundETH(2 ether, user);
    }
}
