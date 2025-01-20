// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/SharePriceOracle.sol";
import "../src/MaxLzEndpoint.sol";

/*
contract DeploymentScript is Script {
    function run() public {
        // address LzOptimism = 0x1a44076050125825900e736c501f859c50fE728c; EID = 30213
        // address LzPolygon = 0x1a44076050125825900e736c501f859c50fE728c; EID = 30109

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy SharePriceOracle
        SharePriceOracle sharePriceOracle =
            new SharePriceOracle(uint32(block.chainid), address(0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1));
        console.log("SharePriceOracle deployed to:", address(sharePriceOracle));

        // Deploy MaxLzEndpoint
        MaxLzEndpoint maxLzEndpoint = new MaxLzEndpoint(
            address(0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1), //owner
            address(0x6EDCE65403992e310A62460808c4b910D972f10f), // LZEndpoint
            address(sharePriceOracle)
        );
        console.log("MaxLzEndpoint deployed to:", address(maxLzEndpoint));

        sharePriceOracle.grantRole(address(maxLzEndpoint), sharePriceOracle.ENDPOINT_ROLE());
        console.log("Peer set and role granted");

        vm.stopBroadcast();
    }
}
*/
