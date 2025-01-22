// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/MaxLzEndpoint.sol";
import "./libs/ChainConfig.sol";

contract SetPeers is Script {
    error ConfigNotFound(string path);

    struct DeploymentInfo {
        address oracle;
        address endpoint;
        address admin;
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
    }

    function getDeploymentInfo(
        string memory networkName,
        uint32 chainId
    ) internal view returns (DeploymentInfo memory info) {
        string memory path = string.concat(
            "deployments/",
            networkName,
            "_",
            vm.toString(chainId),
            ".json"
        );

        if (!vm.exists(path)) {
            revert ConfigNotFound(path);
        }

        string memory json = vm.readFile(path);

        info.oracle = vm.parseJsonAddress(json, ".oracle");
        info.endpoint = vm.parseJsonAddress(json, ".endpoint");
        info.admin = vm.parseJsonAddress(json, ".admin");
        info.chainId = uint32(vm.parseJsonUint(json, ".chainId"));
        info.lzEndpointId = uint32(vm.parseJsonUint(json, ".lzEndpointId"));
        info.lzEndpoint = vm.parseJsonAddress(json, ".lzEndpoint");

        return info;
    }

    function run() external {
        ChainConfig.Config memory config = ChainConfig.getConfig(block.chainid);

        string memory deploymentPath = string.concat(
            "deployments/",
            config.name,
            "_",
            vm.toString(config.chainId),
            ".json"
        );
        string memory json = vm.readFile(deploymentPath);
        address endpointAddress = vm.parseJsonAddress(json, ".endpoint");

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(endpointAddress));
        uint256[] memory targetEndpointIds = vm.envUint(
            "TARGET_ENDPOINT_IDS",
            ","
        );

        for (uint256 i = 0; i < targetEndpointIds.length; i++) {
            // Find matching config for endpoint ID
            uint32 targetLzId = uint32(targetEndpointIds[i]);
            ChainConfig.Config memory targetConfig = ChainConfig
                .getConfigByLzId(targetLzId);

            string memory targetPath = string.concat(
                "deployments/",
                targetConfig.name,
                "_",
                vm.toString(targetConfig.chainId),
                ".json"
            );

            string memory targetJson = vm.readFile(targetPath);
            address targetEndpoint = vm.parseJsonAddress(
                targetJson,
                ".endpoint"
            );

            bytes32 targetPeer = bytes32(uint256(uint160(targetEndpoint)));
            endpoint.setPeer(targetLzId, targetPeer);

            console.log(
                string.concat(
                    "Set peer for ",
                    targetConfig.name,
                    " (lzId: ",
                    vm.toString(targetLzId),
                    ") to: ",
                    vm.toString(targetEndpoint)
                )
            );
        }

        vm.stopBroadcast();
    }
}
