// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Constants } from "../script/libs/Constants.sol";
import { MaxLzEndpoint } from "../src/MaxLzEndpoint.sol";
import { stdJson } from "forge-std/StdJson.sol";

contract ConfigurePeers is Script {
    using stdJson for string;

    function run() external {
        // This script is for Optimism, Arbitrum, and Polygon
        require(
            block.chainid == Constants.OPTIMISM ||
            block.chainid == Constants.ARBITRUM ||
            block.chainid == Constants.POLYGON,
            "This script is only for Optimism, Arbitrum, or Polygon"
        );

        (,, address maxLzAddress) = Constants.getChainConfig(uint32(block.chainid));
        (uint32 baseLzId, , address baseMazLzEndpointAddress) = Constants.getChainConfig(8453);

        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        MaxLzEndpoint maxLzEndpoint = MaxLzEndpoint(payable(maxLzAddress));

        vm.startBroadcast(deployerPrivateKey);

        // Set Base's MaxLzEndpoint as peer
        maxLzEndpoint.setPeer(baseLzId, bytes32(uint256(uint160(baseMazLzEndpointAddress))));
        console2.log("Setting Base as peer on chain:", block.chainid);
        console2.log("Base LZ ID:", baseLzId);
        console2.log("Base MaxLzEndpoint:", maxLzAddress);
        console2.log("Base LZ Endpoint:", baseMazLzEndpointAddress);

        vm.stopBroadcast();
    }
} 
