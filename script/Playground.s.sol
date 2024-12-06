// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {SharePriceOracle} from "../src/SharePriceOracle.sol";
import {MockERC4626} from "../test/mocks/MockERC4626.sol";
import {VaultReport} from "../src/interfaces/ISharePriceOracle.sol";
import {MsgCodec} from "../src/libs/MsgCodec.sol";

contract SendSharePricesScript is Script {
   address constant OP_ORACLE = 0x29Aa29D05911dc288D67b0D86e10fFa2C7d56be8;
   address constant OP_MAX_LZ = 0xf5899AB04B29deaaabA54330b118823130c8319E;
   address constant OP_VAULT = 0xF726bb4A4934B7c4FA8F671Cf558932C5e1696E5;
   uint32 constant BASE_EID = 40245;

   function run() public {
       uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
       vm.startBroadcast(deployerPrivateKey);

       MockERC4626 vault = MockERC4626(OP_VAULT);
       vault.setMockSharePrice(1300000);
    
       address[] memory vaults = new address[](1);
       vaults[0] = OP_VAULT;

       MaxLzEndpoint endpoint = MaxLzEndpoint(payable(OP_MAX_LZ));
       SharePriceOracle oracle = SharePriceOracle(OP_ORACLE);
    
       bytes memory options = endpoint.newOptions();
       options = endpoint.addExecutorLzReceiveOption(options, 500000, 200000);

       VaultReport[] memory reports = oracle.getSharePrices(vaults, 0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1);
    
       bytes memory message = MsgCodec.encodeVaultReports(1, reports, options);

       uint256 fee = endpoint.estimateFees(
           BASE_EID,
           1,
           message,
           options
       );
    
       console.log("Fee:", fee);

       endpoint.sendSharePrices{value: fee + 1e15}(
           BASE_EID,
           vaults,
           options,
           0x94aBa23b9Bbfe7bb62A9eB8b1215D72b5f6F33a1
       );

       console.log("Message sent");

       vm.stopBroadcast();
   }
}
