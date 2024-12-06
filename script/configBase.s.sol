// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {SharePriceOracle} from "../src/SharePriceOracle.sol";

contract configBaseScript is Script {
    address constant SHARE_PRICE_ORACLE = 0xdff2Eb8611f281Cda11380f73B0034817Edcd0b6;
    address constant BASE_MAX_LZ = 0x631267EdD807f287aEd005c72C2Eaf1D64aFA61b;

    address constant OP_MAX_LZ = 0xf5899AB04B29deaaabA54330b118823130c8319E;
    uint32 constant OP_EID = 40232;
 

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(BASE_MAX_LZ));

        bytes32 opPeer = bytes32(uint256(uint160(OP_MAX_LZ)));

        endpoint.setPeer(OP_EID, opPeer);

        SharePriceOracle oracle = SharePriceOracle(SHARE_PRICE_ORACLE);
        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());

        bytes32 setPeer = endpoint.peers(OP_EID);
        console.log("Set OP peer on Base:", address(uint160(uint256(setPeer))));

        vm.stopBroadcast();
    }
}
