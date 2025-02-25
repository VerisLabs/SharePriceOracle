// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SharePriceRouter.sol";
import "../src/interfaces/ISharePriceRouter.sol";

contract SimpleValidate is Script {
    function run() external {
        // Router address on Base
        address routerAddress = 0x366d324370B34c1604b4b867F5D93925245d4464;
        SharePriceRouter router = SharePriceRouter(routerAddress);
        
        console.log("Validating SharePriceRouter at:", routerAddress);
        
        // Define test parameters
        uint32 optimismChainId = 10;
        address optimismVault = 0x81C9A7B55A4df39A9B7B5F781ec0e53539694873;
        address optimismUSDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // USDC.e (bridged)
        
        // Base USDC for testing cross-chain conversion
        address baseUSDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        
        // Check cross-chain asset mapping
        bytes32 key = keccak256(abi.encodePacked(optimismChainId, optimismUSDC));
        address localEquivalent = router.crossChainAssetMap(key);
        console.log("Cross-chain mapping for Optimism USDC.e:");
        console.log("  Local equivalent:", localEquivalent);
        
        if (localEquivalent == address(0)) {
            console.log("  No mapping found! This is the issue.");
            console.log("  The system is trying to use the original USDC.e address for price feeds.");
        } else {
            console.log("  Mapping exists to:", localEquivalent);
        }
        
        // Test getLatestPrice with Optimism USDC.e directly
        console.log("\nTesting getLatestPrice with Optimism USDC.e directly:");
        try router.getLatestPrice(optimismUSDC, true) returns (uint256 price, uint256 timestamp, bool isUSD) {
            console.log("  Price:", price);
            console.log("  Timestamp:", timestamp);
            console.log("  Is USD:", isUSD);
        } catch Error(string memory reason) {
            console.log("  Failed:", reason);
        } catch {
            console.log("  Failed with unknown error");
        }
        
        // Test getLatestPrice with Base USDC
        console.log("\nTesting getLatestPrice with Base USDC:");
        try router.getLatestPrice(baseUSDC, true) returns (uint256 price, uint256 timestamp, bool isUSD) {
            console.log("  Price:", price);
            console.log("  Timestamp:", timestamp);
            console.log("  Is USD:", isUSD);
        } catch Error(string memory reason) {
            console.log("  Failed:", reason);
        } catch {
            console.log("  Failed with unknown error");
        }
        
        // Get the vault report
        console.log("\nChecking vault report:");
        bytes32 priceKey = router.getPriceKey(optimismChainId, optimismVault);
        console.log("  Price key:", vm.toString(priceKey));
        
        try router.getLatestSharePriceReport(optimismChainId, optimismVault) returns (VaultReport memory report) {
            console.log("  Share price:", report.sharePrice);
            console.log("  Asset:", report.asset);
            console.log("  Asset decimals:", report.assetDecimals);
        } catch {
            console.log("  Failed to get vault report");
        }
    }
} 