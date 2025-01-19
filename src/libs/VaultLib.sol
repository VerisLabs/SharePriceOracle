// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VaultReport} from "../interfaces/ISharePriceOracle.sol";
import {IERC4626} from "../interfaces/IERC4626.sol";
import {IERC20Metadata} from "../interfaces/IERC20Metadata.sol";

library VaultLib {
    function getVaultSharePrice(
        address _vaultAddress,
        address _rewardsDelegate,
        uint32 chainId
    ) internal view returns (VaultReport memory) {
        try IERC4626(_vaultAddress).asset() returns (address asset_) {
            try IERC20Metadata(asset_).decimals() returns (uint8 assetDecimals) {
                try IERC4626(_vaultAddress).convertToAssets(10 ** assetDecimals)
                returns (uint256 sharePrice) {
                    return VaultReport({
                        lastUpdate: uint64(block.timestamp),
                        chainId: chainId,
                        vaultAddress: _vaultAddress,
                        sharePrice: sharePrice,
                        rewardsDelegate: _rewardsDelegate,
                        asset: asset_,
                        assetDecimals: assetDecimals
                    });
                } catch {}
            } catch {}
        } catch {}

        return VaultReport({
            lastUpdate: uint64(block.timestamp),
            chainId: chainId,
            vaultAddress: _vaultAddress,
            sharePrice: 0,
            rewardsDelegate: _rewardsDelegate,
            asset: address(0),
            assetDecimals: 0
        });
    }
}
