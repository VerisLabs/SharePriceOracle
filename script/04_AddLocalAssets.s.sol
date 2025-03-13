// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Script } from "forge-std/Script.sol";
import { console2 } from "forge-std/console2.sol";
import { Constants } from "../script/libs/Constants.sol";
import { SharePriceRouter } from "../src/SharePriceRouter.sol";

contract AddLocalAssets is Script {
    function run() external {
        // Only run on Base chain
        require(block.chainid == Constants.BASE, "This script is only for Base chain");

        // Load configuration
        uint256 relayerPrivateKey = vm.envUint("PRIVATE_KEY");
        address routerAddress = vm.envAddress("ROUTER_ADDRESS");
        SharePriceRouter router = SharePriceRouter(routerAddress);

        vm.startBroadcast(relayerPrivateKey);

        router.setCrossChainAssetMapping(
            Constants.ARBITRUM, 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
        );
        console2.log("Mapped asset");

        //       router.setLocalAssetConfig(
        //           0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        //           0xA6779d614d351fC52ae6D8558Ecd651763Af33DE,
        //           0x7e860098F58bBFC8648a4311b374B1D669a2bc6B,
        //           0,
        //           true
        //       );
        //       console2.log("Mapped localAsset asset");

        vm.stopBroadcast();
    }
}
