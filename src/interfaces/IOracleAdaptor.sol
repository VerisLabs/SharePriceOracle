// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct PriceReturnData {
    uint240 price;        // Price normalized to WAD (1e18)
    bool hadError;        // Error flag - keeping consistent with your existing naming
    bool inUSD;           // Price denomination
}

interface IOracleAdaptor {
    /**
     * @notice Gets the price for an asset
     * @param asset The asset to get the price for
     * @param inUSD Whether to get the price in USD
     * @return PriceReturnData Structure containing price and metadata
     */
    function getPrice(
        address asset,
        bool inUSD
    ) external view returns (PriceReturnData memory);

    /// @notice Whether an asset is supported by the Oracle Adaptor or not.
    /// @dev Asset => Supported by adaptor.
    function isSupportedAsset(address asset) external view returns (bool);
}
