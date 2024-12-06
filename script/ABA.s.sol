// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {SharePriceOracle, VaultReport} from "../src/SharePriceOracle.sol";
import {MsgCodec} from "../src/libs/MsgCodec.sol";

contract RequestSharePricesScript is Script {
    address constant BASE_ORACLE = 0xdff2Eb8611f281Cda11380f73B0034817Edcd0b6;
    address constant BASE_MAX_LZ = 0x631267EdD807f287aEd005c72C2Eaf1D64aFA61b;
    address constant OP_VAULT = 0xF726bb4A4934B7c4FA8F671Cf558932C5e1696E5;
    uint32 constant OP_EID = 40232;
    uint32 constant BASE_EID = 40245;
    uint16 constant ABA_TYPE = 2;
    uint16 constant AB_TYPE = 1;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(BASE_MAX_LZ));
        address[] memory vaults = new address[](1);
        vaults[0] = OP_VAULT;

        bytes memory extraReturnOptions = endpoint.newOptions();

        extraReturnOptions = endpoint.addExecutorLzReceiveOption(
            extraReturnOptions,
            1_000_000,
            7_000_000
        );

        uint256 returnFee = 180765630679625;

        bytes memory extraSendOptions = endpoint.newOptions();
        extraSendOptions = endpoint.addExecutorLzReceiveOption(
            extraSendOptions,
            1_000_000,
            uint128(returnFee * 2)
        );

        bytes memory requestMessage = MsgCodec.encodeVaultAddresses(
            ABA_TYPE,
            vaults,
            0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1,
            extraReturnOptions
        );

        uint256 sendFee = endpoint.estimateFees(
            OP_EID,
            ABA_TYPE,
            requestMessage,
            extraSendOptions
        );

        uint256 baseFee = sendFee + returnFee;
        uint256 buffer = (baseFee * 30) / 100;
        uint256 totalFee = baseFee + buffer;

        endpoint.requestSharePrices{value: totalFee}(
            OP_EID,
            vaults,
            extraSendOptions,
            extraReturnOptions,
            0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1
        );

        vm.stopBroadcast();
    }
}
