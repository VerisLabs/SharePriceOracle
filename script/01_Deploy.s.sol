// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Constants} from "../script/libs/Constants.sol";
import {SharePriceRouter} from "../src/SharePriceRouter.sol";
import {ChainlinkAdapter} from "../src/adapters/Chainlink.sol";
import {Api3Adapter} from "../src/adapters/Api3.sol";
import {MaxLzEndpoint} from "../src/MaxLzEndpoint.sol";
import {LibString} from "@solady/utils/LibString.sol";

contract Deploy is Script {
    using LibString for uint256;
    using LibString for address;

    // Deployment state
    MaxLzEndpoint public maxLzEndpoint;
    SharePriceRouter public router;
    address public admin;
    address public lzEndpointAddress;
    address public oracleAddress;
    ChainlinkAdapter public chainlinkAdapter;
    Api3Adapter public api3Adapter;

    function run() external {
        // Load configuration
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        admin = vm.envAddress("ADMIN_ADDRESS");
        lzEndpointAddress = vm.envAddress("LZ_ENDPOINT_ADDRESS");
        oracleAddress = vm.envAddress("ORACLE_ADDRESS");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy core contracts
        _deployCore();

        // Deploy chain-specific contracts
        if (block.chainid == Constants.BASE) {
            _deployOnBase();
        } 

        // Save deployment info
        _saveDeployment();

        vm.stopBroadcast();
    }

    function _deployCore() internal {
        // Deploy SharePriceRouter
        router = new SharePriceRouter(admin);
        _logDeploymentInfo();

        // Deploy MaxLzEndpoint
        maxLzEndpoint = new MaxLzEndpoint(admin, lzEndpointAddress, address(router));
        console2.log("MaxLzEndpoint deployed at:", address(maxLzEndpoint));
        console2.log("Using LayerZero Endpoint:", lzEndpointAddress);

        // Setup core permissions
        router.grantRole(admin, router.ADMIN_ROLE());
        router.grantRole(address(maxLzEndpoint), router.ENDPOINT_ROLE());
        router.grantRole(oracleAddress, router.ENDPOINT_ROLE());
    }

    function _deployOnBase() internal {
        console2.log("");
        console2.log("=== Base Chain Specific Deployments ===");

        // Deploy adapters
        chainlinkAdapter = new ChainlinkAdapter(admin, address(router), address(router));
        console2.log("ChainlinkAdapter deployed at:", address(chainlinkAdapter));

        api3Adapter = new Api3Adapter(
            admin, 
            address(router), 
            address(router), 
            0x4200000000000000000000000000000000000006
        );
        console2.log("Api3Adapter deployed at:", address(api3Adapter));

        // Setup adapter permissions
        router.grantRole(address(chainlinkAdapter), router.ADAPTER_ROLE());
        router.grantRole(address(api3Adapter), router.ADAPTER_ROLE());

        chainlinkAdapter.grantRole(address(router), chainlinkAdapter.ORACLE_ROLE());
        chainlinkAdapter.grantRole(admin, chainlinkAdapter.ADMIN_ROLE());
        api3Adapter.grantRole(address(router), api3Adapter.ORACLE_ROLE());
        api3Adapter.grantRole(admin, api3Adapter.ADMIN_ROLE());

        _logPermissions();
    }

    function _saveDeployment() internal {
        string memory chainName = _getChainName();
        string memory timestamp = block.timestamp.toString();
        
        // Create directory structure
        string memory deploymentDir = string.concat("deployments/", chainName, "/", timestamp);
        vm.createDir(deploymentDir, true);
        
        // Write addresses file
        string memory addressesPath = string.concat(deploymentDir, "/addresses.json");
        vm.writeFile(addressesPath, _generateDeploymentJson());

        // Create/Update latest symlink
        string memory latestPath = string.concat("deployments/", chainName, "/latest");
        //vm.removeFile(latestPath); // Remove old symlink if exists
        vm.createDir(latestPath, true); // Create latest directory
        vm.writeFile(
            string.concat(latestPath, "/addresses.json"),
            _generateDeploymentJson()
        );

        console2.log("");
        console2.log("Deployment addresses saved to:", addressesPath);
        console2.log("Latest symlink updated at:", latestPath);
        console2.log("=== Deployment Complete ===");
    }

    function _generateDeploymentJson() internal view returns (string memory) {
        string memory json = "{";
        json = string.concat(json, '"timestamp":', block.timestamp.toString(), ",");
        json = string.concat(json, '"chainId":', block.chainid.toString(), ",");
        json = string.concat(json, '"deployer":"', msg.sender.toHexString(), '",');
        json = string.concat(json, '"contracts":{');
        json = string.concat(json, '"router":"', address(router).toHexString(), '",');
        json = string.concat(json, '"maxLzEndpoint":"', address(maxLzEndpoint).toHexString(), '"');
        
        if (block.chainid == Constants.BASE) {
            json = string.concat(json, ',');
            json = string.concat(json, '"chainlinkAdapter":"', address(chainlinkAdapter).toHexString(), '",');
            json = string.concat(json, '"api3Adapter":"', address(api3Adapter).toHexString(), '"');
        }
        
        json = string.concat(json, "}}");
        return json;
    }

    function _logDeploymentInfo() internal view {
        console2.log("=== Deployment Info ===");
        console2.log("Network:", block.chainid);
        console2.log("Deployer:", msg.sender);
        console2.log("Admin:", admin);
        console2.log("");
        console2.log("SharePriceRouter deployed at:", address(router));
    }

    function _logPermissions() internal pure {
        console2.log("");
        console2.log("=== Permissions Granted ===");
        console2.log("ChainlinkAdapter granted ADAPTER_ROLE");
        console2.log("Api3Adapter granted ADAPTER_ROLE");
        console2.log("Router granted ORACLE_ROLE on both adapters");
    }

    function _getChainName() internal view returns (string memory) {
        if (block.chainid == Constants.BASE) return "base";
        if (block.chainid == Constants.OPTIMISM) return "optimism";
        if (block.chainid == Constants.ARBITRUM) return "arbitrum";
        if (block.chainid == Constants.POLYGON) return "polygon";
        return "unknown";
    }
}
