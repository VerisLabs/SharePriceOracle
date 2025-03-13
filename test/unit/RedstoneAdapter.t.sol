// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../../src/adapters/Redstone.sol";

contract MockRedstonePayload is Test {
    function getRedstonePayload(
        // dataFeedId:value:decimals
        string memory priceFeed
    ) public returns (bytes memory) {
        string[] memory args = new string[](3);
        args[0] = "node";
        args[1] = "getRedstonePayload.js";
        args[2] = priceFeed;

        // Add debug logging
        emit log_string("Executing getRedstonePayload with args:");
        emit log_string(args[1]);
        emit log_string(args[2]);
        
        bytes memory payload = vm.ffi(args);
        
        // Add debug logging for payload
        emit log_bytes(payload);
        
        require(payload.length > 0, "Redstone payload is empty");
        return payload;
    }
}

contract RedstoneAdapterTest is Test, MockRedstonePayload {
    RedstoneAdapter public adapter;

    function setUp() public {
        adapter = new RedstoneAdapter();
    }

    function testOracleData() public {
        bytes memory redstonePayload = getRedstonePayload("BTC:120:8,ETH:69:8");

        bytes memory encodedFunction = abi.encodeWithSignature(
            "getPrice(bytes32)",
            bytes32("BTC")
        );
        bytes memory encodedFunctionWithRedstonePayload = abi.encodePacked(
            encodedFunction,
            redstonePayload
        );

        // Securely getting oracle value
        (bool success, bytes memory returnData) = address(adapter).call(
            encodedFunctionWithRedstonePayload
        );
        assertEq(success, true);
        
        uint256 price = abi.decode(returnData, (uint256));
        // 120 * 10 ** 8
        assertEq(price, 12000000000);
    }
}