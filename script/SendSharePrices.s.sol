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

        info.oracle = vm.parseJsonAddress(json, ".oracle");
        info.endpoint = vm.parseJsonAddress(json, ".endpoint");
        info.admin = vm.parseJsonAddress(json, ".admin");
        info.chainId = uint32(vm.parseJsonUint(json, ".chainId"));
        info.lzEndpointId = uint32(vm.parseJsonUint(json, ".lzEndpointId"));
        info.lzEndpoint = vm.parseJsonAddress(json, ".lzEndpoint");

        return info;
    }

    function prepareLzOptions(MaxLzEndpoint endpoint) internal view returns (bytes memory) {
        bytes memory options = endpoint.newOptions();
        return endpoint.addExecutorLzReceiveOption(
            options, uint128(vm.envUint("LZ_GAS_LIMIT")), uint128(vm.envUint("LZ_NATIVE_VALUE"))
        );
    }

    function getVaultAddresses() internal view returns (address[] memory vaults) {
        string[] memory vaultAddrs = vm.envString("VAULT_ADDRESSES", ",");
        vaults = new address[](vaultAddrs.length);
        for (uint256 i = 0; i < vaultAddrs.length; i++) {
            vaults[i] = vm.parseAddress(vaultAddrs[i]);
        }
    }

    function run() external {
        // Get chain configs
        ChainConfig.Config memory srcChain = ChainConfig.getConfig(block.chainid);
        uint256 dstChainId = vm.envUint("DST_CHAIN_ID");
        ChainConfig.Config memory dstChain = ChainConfig.getConfig(dstChainId);

        // Load deployment info
        DeploymentInfo memory srcInfo = getDeploymentInfo(srcChain.name, srcChain.chainId);

        // Start broadcast
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Get contract instances
        MaxLzEndpoint endpoint = MaxLzEndpoint(payable(srcInfo.endpoint));
        SharePriceOracle oracle = SharePriceOracle(srcInfo.oracle);

        // Get vault addresses and prepare LZ options
        address[] memory vaults = getVaultAddresses();
        bytes memory options = prepareLzOptions(endpoint);
        address rewardsDelegate = vm.envAddress("REWARDS_DELEGATE");

        // Get vault reports and encode message
        VaultReport[] memory reports = oracle.getSharePrices(vaults, rewardsDelegate);
        bytes memory message = MsgCodec.encodeVaultReports(1, reports, options);

        // Calculate fees
        uint256 fee = endpoint.estimateFees(dstChain.lzEndpointId, 1, message, options);
        uint256 feeWithBuffer = fee + (fee * 10) / 100; // 10% buffer

        // Log transaction details
        console.log("\nTransaction Summary");
        console.log("==================");
        console.log("From:", srcChain.name);
        console.log("To:", dstChain.name);
        console.log("Vaults:", vaults.length);
        console.log("Fee:", fee);

        endpoint.sendSharePrices{ value: feeWithBuffer }(dstChain.lzEndpointId, vaults, options, rewardsDelegate);

        console.log("Message sent");

        vm.stopBroadcast();
    }
}
