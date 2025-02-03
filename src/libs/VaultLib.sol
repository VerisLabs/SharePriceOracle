// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { VaultReport } from "../interfaces/ISharePriceOracle.sol";
import { IERC4626 } from "../interfaces/IERC4626.sol";
import { IERC20Metadata } from "../interfaces/IERC20Metadata.sol";

/// @title VaultLib
/// @notice Library for interacting with ERC4626 vaults and retrieving share prices
/// @dev Handles graceful failures for non-compliant or failing vaults
library VaultLib {
    /// @notice Retrieves the current share price and metadata for an ERC4626 vault
    /// @dev Uses try-catch blocks to handle potential failures in vault interactions
    /// @param _vaultAddress Address of the ERC4626 vault
    /// @param _rewardsDelegate Address to delegate rewards to (if applicable)
    /// @param chainId The chain ID where the vault is deployed
    /// @return VaultReport A struct containing vault share price and metadata
    /// @custom:security Returns a valid report with 0 share price if any operation fails
    function getVaultSharePrice(
        address _vaultAddress,
        address _rewardsDelegate,
        uint32 chainId
    )
        internal
        view
        returns (VaultReport memory)
    {
        try IERC4626(_vaultAddress).asset() returns (address asset_) {
            try IERC20Metadata(asset_).decimals() returns (uint8 assetDecimals) {
                try IERC4626(_vaultAddress).convertToAssets(10 ** assetDecimals) returns (uint256 sharePrice) {
                    return VaultReport({
                        lastUpdate: uint64(block.timestamp),
                        chainId: chainId,
                        vaultAddress: _vaultAddress,
                        sharePrice: sharePrice,
                        rewardsDelegate: _rewardsDelegate,
                        asset: asset_,
                        assetDecimals: assetDecimals
                    });
                } catch { }
            } catch { }
        } catch { }

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
