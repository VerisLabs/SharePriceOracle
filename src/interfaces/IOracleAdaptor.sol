// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

struct PriceReturnData {
    uint240 price;        // Price normalized to WAD (1e18)
    bool hadError;        // Error flag - keeping consistent with your existing naming
    bool inUSD;           // Price denomination
}

interface IOracleAdaptor {
    /// @notice Called by OracleRouter to price an asset.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @param getLower A boolean to determine if lower of two oracle prices
    ///                 should be retrieved.
    /// @return A structure containing the price, error status,
    ///         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
    ) external view returns (PriceReturnData memory);

    /// @notice Whether an asset is supported by the Oracle Adaptor or not.
    /// @dev Asset => Supported by adaptor.
    function isSupportedAsset(address asset) external view returns (bool);
}
