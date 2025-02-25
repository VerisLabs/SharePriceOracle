// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../src/SharePriceRouter.sol";
import "../src/interfaces/ISharePriceRouter.sol";
import "./libs/ChainConfig.sol";

contract SendSharePrices is Script {
    error ConfigNotFound(string path);

    struct DeploymentInfo {
        address router;
        address endpoint;
        address chainlinkAdapter;
        address api3Adapter;
        address admin;
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
    }

    function getDeploymentInfo(
        string memory networkName,
        uint32 chainId
    )
        internal
        view
        returns (DeploymentInfo memory info)
    {
        string memory path = string.concat("deployments/", networkName, "_", vm.toString(chainId), ".json");

        if (!vm.exists(path)) {
            revert ConfigNotFound(path);
        }

        string memory json = vm.readFile(path);

        info.router = vm.parseJsonAddress(json, ".router");
        info.endpoint = vm.parseJsonAddress(json, ".endpoint");
        info.chainlinkAdapter = vm.parseJsonAddress(json, ".chainlinkAdapter");
        info.api3Adapter = vm.parseJsonAddress(json, ".api3Adapter");
        info.admin = vm.parseJsonAddress(json, ".admin");
        info.chainId = uint32(vm.parseJsonUint(json, ".chainId"));
        info.lzEndpointId = uint32(vm.parseJsonUint(json, ".lzEndpointId"));
        info.lzEndpoint = vm.parseJsonAddress(json, ".lzEndpoint");

        return info;
    }

    function run() external {
        // Load admin private key to grant roles
        uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
        address adminAddress = vm.addr(adminPrivateKey);
        
        // Get the current chain's deployment info
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);
        console.log("Running on chain:", config.name);
        
        DeploymentInfo memory info = getDeploymentInfo(config.name, config.chainId);
        console.log("Router address:", info.router);
        console.log("Admin address:", adminAddress);
        
        // Define USDC addresses for each chain
        address optimismUSDC = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607; // Optimism USDC.e (bridged)
        address arbitrumUSDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // Arbitrum USDT
        
        // Create Optimism vault report
        VaultReport[] memory optimismReports = new VaultReport[](1);
        optimismReports[0] = VaultReport({
            chainId: 10, // Optimism
            vaultAddress: 0x81C9A7B55A4df39A9B7B5F781ec0e53539694873,
            asset: optimismUSDC,
            assetDecimals: 6, // USDC has 6 decimals
            sharePrice: 1134773,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873
        });
        
        // Create Arbitrum vault report
        VaultReport[] memory arbitrumReports = new VaultReport[](1);
        arbitrumReports[0] = VaultReport({
            chainId: 42161, // Arbitrum
            vaultAddress: 0x16A70933c3ea281d7A8A30349808a4C50e81E377,
            asset: arbitrumUSDT,
            assetDecimals: 6, // USDT has 6 decimals
            sharePrice: 1039736,
            lastUpdate: uint64(block.timestamp),
            rewardsDelegate: 0x88190A6F759CF1115e0c6BCF4Eea1Fef0994e873
        });
        
        // Start broadcast with admin key
        vm.startBroadcast(adminPrivateKey);
        
        // Get the router contract
        SharePriceRouter router = SharePriceRouter(info.router);
        
        // Grant ENDPOINT_ROLE to admin address temporarily
        uint256 ENDPOINT_ROLE = router.ENDPOINT_ROLE();
        console.log("Granting ENDPOINT_ROLE to admin address");
        router.grantRole(adminAddress, ENDPOINT_ROLE);
        
        // Update share prices for Optimism
        console.log("Updating share prices for Optimism (Chain ID: 10)");
        console.log("Vault address:", optimismReports[0].vaultAddress);
        console.log("Share price:", optimismReports[0].sharePrice);
        
        try router.updateSharePrices(10, optimismReports) {
            console.log("Successfully updated Optimism share prices");
            
            // Verify the data was stored correctly
            bytes32 optimismKey = router.getPriceKey(10, optimismReports[0].vaultAddress);
            console.log("Optimism price key:", vm.toString(optimismKey));
            
            VaultReport memory storedReport = router.getLatestSharePriceReport(10, optimismReports[0].vaultAddress);
            console.log("Stored share price:", storedReport.sharePrice);
            console.log("Stored asset:", storedReport.asset);
            
            // Try to get the latest share price
            try router.getLatestSharePrice(10, optimismReports[0].vaultAddress, optimismUSDC) returns (uint256 price, uint64 timestamp) {
                console.log("Retrieved share price:", price);
                console.log("Retrieved timestamp:", timestamp);
            } catch Error(string memory reason) {
                console.log("Failed to get latest share price:", reason);
            } catch {
                console.log("Failed to get latest share price with unknown error");
            }
        } catch Error(string memory reason) {
            console.log("Failed to update Optimism share prices:", reason);
        } catch {
            console.log("Failed to update Optimism share prices with unknown error");
        }
        
        // Update share prices for Arbitrum
        console.log("Updating share prices for Arbitrum (Chain ID: 42161)");
        console.log("Vault address:", arbitrumReports[0].vaultAddress);
        console.log("Share price:", arbitrumReports[0].sharePrice);
        
        try router.updateSharePrices(42161, arbitrumReports) {
            console.log("Successfully updated Arbitrum share prices");
            
            // Verify the data was stored correctly
            bytes32 arbitrumKey = router.getPriceKey(42161, arbitrumReports[0].vaultAddress);
            console.log("Arbitrum price key:", vm.toString(arbitrumKey));
            
            VaultReport memory storedReport = router.getLatestSharePriceReport(42161, arbitrumReports[0].vaultAddress);
            console.log("Stored share price:", storedReport.sharePrice);
            console.log("Stored asset:", storedReport.asset);
            
            // Try to get the latest share price
            try router.getLatestSharePrice(42161, arbitrumReports[0].vaultAddress, arbitrumUSDT) returns (uint256 price, uint64 timestamp) {
                console.log("Retrieved share price:", price);
                console.log("Retrieved timestamp:", timestamp);
            } catch Error(string memory reason) {
                console.log("Failed to get latest share price:", reason);
            } catch {
                console.log("Failed to get latest share price with unknown error");
            }
        } catch Error(string memory reason) {
            console.log("Failed to update Arbitrum share prices:", reason);
        } catch {
            console.log("Failed to update Arbitrum share prices with unknown error");
        }
        
        // Revoke ENDPOINT_ROLE from admin address
        console.log("Revoking ENDPOINT_ROLE from admin address");
        router.revokeRole(adminAddress, ENDPOINT_ROLE);
        
        vm.stopBroadcast();
    }
} 