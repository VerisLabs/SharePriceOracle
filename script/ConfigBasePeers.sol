// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/MaxLzEndpoint.sol";

/**
 * @title ConfigBasePeers
 * @notice Simple script to configure the peers of Optimism and Arbitrum on Base
 * @dev This script should be run on Base to configure its endpoint to communicate with Optimism and Arbitrum
 */
contract ConfigBasePeers is Script {
    function run() external {
        console.log("Configuring Base peers for Optimism and Arbitrum");

        // Hardcoded values - copy-pasted from deployment files
        address baseEndpoint = 0x992234A3CEfad5D538F2426EB350Cfd3Cc67CCC4; // From Base_8453.json
        address optimismEndpoint = 0x9286Fc03D6e7A23FC7201EE287a77b942F3c9663; // From Optimism_10.json
        address arbitrumEndpoint = 0x2f9e01b1E344aFA1cF3BDefD72C507CC6fF3b396; // From Arbitrum_42161.json

        console.log("Base endpoint:", baseEndpoint);
        console.log("Optimism endpoint:", optimismEndpoint);
        console.log("Arbitrum endpoint:", arbitrumEndpoint);

        // Use PRIVATE_KEY for admin operations
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(adminPrivateKey);

        // Get the MaxLzEndpoint contract
        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(baseEndpoint));

        // Configure peers - only using setPeer

        // Set Optimism peer (LZ ID: 30111)
        try endpoint.setPeer(30_111, bytes32(uint256(uint160(optimismEndpoint)))) {
            console.log("Successfully set peer for Optimism");
        } catch Error(string memory reason) {
            console.log("Failed to set peer for Optimism:", reason);
        } catch {
            console.log("Failed to set peer for Optimism with unknown error");
        }

        // Set Arbitrum peer (LZ ID: 30110)
        try endpoint.setPeer(30_110, bytes32(uint256(uint160(arbitrumEndpoint)))) {
            console.log("Successfully set peer for Arbitrum");
        } catch Error(string memory reason) {
            console.log("Failed to set peer for Arbitrum:", reason);
        } catch {
            console.log("Failed to set peer for Arbitrum with unknown error");
        }

        vm.stopBroadcast();

        console.log("Base peer configuration completed");
    }
}
