// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import "../src/MaxLzEndpoint.sol";
import "../src/SharePriceOracle.sol";
import "../test/mocks/MockERC4626.sol";
import "../src/interfaces/ISharePriceOracle.sol";
import "../src/libs/MsgCodec.sol";
import "./libs/ChainConfig.sol";

contract SendSharePrices is Script {
    error ConfigNotFound(string path);
    error InvalidConfig(string reason);

    struct DeploymentInfo {
        address oracle;
        address endpoint;
        address admin;
        uint32 chainId;
        uint32 lzEndpointId;
        address lzEndpoint;
    }

    struct SendConfig {
        uint128 gasLimit;
        uint128 nativeValue;
        address rewardsDelegate;
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
        // Get current chain config
        ChainConfig.Config memory srcChain = ChainConfig.getConfig(block.chainid);
        
        // Load deployments info for source chain
        DeploymentInfo memory srcInfo = getDeploymentInfo(
            srcChain.name,
            srcChain.chainId
        );

        // Get destination chain info from env
        uint256 dstChainId = vm.envUint("DST_CHAIN_ID");
        ChainConfig.Config memory dstChain = ChainConfig.getConfig(dstChainId);

        // Get deployment info for destination chain
        DeploymentInfo memory dstInfo = getDeploymentInfo(
            dstChain.name,
            dstChain.chainId
        );

        // Load configuration from environment
        SendConfig memory config = SendConfig({
            gasLimit: uint128(vm.envUint("LZ_GAS_LIMIT")),
            nativeValue: uint128(vm.envUint("LZ_NATIVE_VALUE")),
            rewardsDelegate: vm.envAddress("REWARDS_DELEGATE")
        });

        // Load vault addresses from environment
        string[] memory vaultAddrs = vm.envString("VAULT_ADDRESSES", ",");
        address[] memory vaults = new address[](vaultAddrs.length);
        for(uint i = 0; i < vaultAddrs.length; i++) {
            vaults[i] = vm.parseAddress(vaultAddrs[i]);
        }

        // Start broadcast
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Get contract instances
        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(srcInfo.endpoint));
        SharePriceOracle oracle = SharePriceOracle(srcInfo.oracle);

        // Prepare LayerZero options
        bytes memory options = endpoint.newOptions();
        options = endpoint.addExecutorLzReceiveOption(
            options,
            config.gasLimit,
            config.nativeValue
        );

        // Get vault reports
        VaultReport[] memory reports = oracle.getSharePrices(
            vaults,
            config.rewardsDelegate
        );

        // Encode message and estimate fees
        bytes memory message = MsgCodec.encodeVaultReports(1, reports, options);
        uint256 fee = endpoint.estimateFees(
            dstChain.chainId,
            1,
            message,
            options
        );

        // Add buffer to fee
        uint256 feeWithBuffer = fee + (fee * 10) / 100; // 10% buffer

        console.log("\nTransaction Summary:");
        console.log("===================");
        console.log("Source Chain:", srcChain.name);
        console.log("Destination Chain:", dstChain.name);
        console.log("Number of Vaults:", vaults.length);
        console.log("Estimated Fee:", fee);
        console.log("Fee with Buffer:", feeWithBuffer);

        // Send transaction
        endpoint.sendSharePrices{value: feeWithBuffer}(
            dstChain.chainId,
            vaults,
            options,
            config.rewardsDelegate
        );

        console.log("Message sent successfully");
        
        vm.stopBroadcast();
    }
}
