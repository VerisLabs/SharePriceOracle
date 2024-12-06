// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../test/mocks/MockERC20.sol";
import "../test/mocks/MockERC4626.sol";

contract DeployMocksScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MockERC20 (USDC)
        MockERC20 banana = new MockERC20("Banana Coin", "BANANA", 6);
        console.log("MockERC20 (BANANA) deployed to:", address(banana));

        // Deploy MockERC4626 (Vault)
        MockERC4626 vault = new MockERC4626(address(banana), "BANANA Vault", "vBANANA");
        console.log("MockERC4626 (Vault) deployed to:", address(vault));

        // Mint 1M USDC to deployer
        banana.mint(msg.sender, 1_000_000_000);
        console.log("Minted 1M USDC to deployer");

        vm.stopBroadcast();
    }
}
