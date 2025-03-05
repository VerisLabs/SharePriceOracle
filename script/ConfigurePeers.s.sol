// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { AddressBook } from "../src/libs/AddressBook.sol";
import { MaxLzEndpoint } from "../src/MaxLzEndpoint.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract ConfigurePeers is Script {
    using stdJson for string;

    address maxLzAddress;

    function run() external {
        // This script is for Optimism, Arbitrum, and Polygon
        require(
            block.chainid == AddressBook.OPTIMISM ||
            block.chainid == AddressBook.ARBITRUM ||
            block.chainid == AddressBook.POLYGON,
            "This script is only for Optimism, Arbitrum, or Polygon"
        );

        if (block.chainid == AddressBook.OPTIMISM) {
            maxLzAddress = vm.envAddress("OP_MAX_LZ_ENDPOINT_ADDRESS");
        } else if (block.chainid == AddressBook.ARBITRUM) {
            maxLzAddress = vm.envAddress("ARB_MAX_LZ_ENDPOINT_ADDRESS");
        } else if (block.chainid == AddressBook.POLYGON) {
            maxLzAddress = vm.envAddress("POLY_MAX_LZ_ENDPOINT_ADDRESS");
        }

        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address baseMaxLzEndpoint = vm.envAddress("BASE_MAX_LZ_ENDPOINT_ADDRESS");

        MaxLzEndpoint maxLzEndpoint = MaxLzEndpoint(payable(maxLzAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Get Base chain config from ChainConfig library
        (uint32 baseLzId, address baseLzEndpoint,) = AddressBook.getChainConfig(AddressBook.BASE);

        // Set Base's MaxLzEndpoint as peer
        maxLzEndpoint.setPeer(baseLzId, bytes32(uint256(uint160(baseMaxLzEndpoint))));
        console2.log("Setting Base as peer on chain:", block.chainid);
        console2.log("Base LZ ID:", baseLzId);
        console2.log("Base MaxLzEndpoint:", baseMaxLzEndpoint);
        console2.log("Base LZ Endpoint:", baseLzEndpoint);

        vm.stopBroadcast();
    }
} 