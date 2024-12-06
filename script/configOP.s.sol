// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {SharePriceOracle} from "../src/SharePriceOracle.sol";

contract configOPScript is Script {
    address constant SHARE_PRICE_ORACLE =
        0x29Aa29D05911dc288D67b0D86e10fFa2C7d56be8;
    address constant OP_MAX_LZ = 0xf5899AB04B29deaaabA54330b118823130c8319E;

    address constant BASE_MAX_LZ = 0x631267EdD807f287aEd005c72C2Eaf1D64aFA61b;
    uint32 constant BASE_EID = 40245;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(OP_MAX_LZ));
        bytes32 basePeer = bytes32(uint256(uint160(BASE_MAX_LZ)));
        endpoint.setPeer(BASE_EID, basePeer);

        SharePriceOracle oracle = SharePriceOracle(SHARE_PRICE_ORACLE);
        oracle.grantRole(address(endpoint), oracle.ENDPOINT_ROLE());

        bytes32 setPeer = endpoint.peers(BASE_EID);
        console.log("Set Base peer on OP:", address(uint160(uint256(setPeer))));

        vm.stopBroadcast();
    }
}
