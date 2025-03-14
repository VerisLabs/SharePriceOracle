// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;


import { ISharePriceRouter } from "../../interfaces/ISharePriceRouter.sol";
import { BaseOracleAdapter } from "../../libs/base/BaseOracleAdapter.sol";

contract AerodromeBaseAdapter is BaseOracleAdapter{
    /// TYPES ///

    /// @notice Stores configuration data for Uniswap V2 stable style
    ///         Twap price sources.
    /// @param token0 Underlying token0 address.
    /// @param decimals0 Underlying decimals for token0.
    /// @param token1 Underlying token1 address.
    /// @param decimals1 Underlying decimals for token1.
    struct AdapterData {
        address pool;
        address baseToken;
        uint8 baseTokenDecimals;
        uint8 quoteTokenDecimals;
    }

    /// STORAGE ///

    /// @notice Adapter configuration data for pricing an asset.
    /// @dev Stable pool address => AdapterData.
    mapping(address => AdapterData) public adapterData;

    ISharePriceRouter public oracleRouter;

    /// EVENTS ///

    event AerodromePoolAssetAdded(
        address asset, 
        AdapterData assetConfig, 
        bool isUpdate
    );
    event AerodromePoolAssetRemoved(address asset);

    /// ERRORS ///

    error AerodromeAdapter__AssetIsNotSupported();
    error AerodromeAdapter__InvalidAsset();
    error AerodromeAdapter__InvalidPoolAddress();

    /// CONSTRUCTOR ///

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter
    )
    BaseOracleAdapter(_admin, _oracle, _oracleRouter) {
        oracleRouter = ISharePriceRouter(
            _oracleRouter
        );
    }


    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of `asset` from Aerodrome pool
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD
    ) external view virtual override returns (ISharePriceRouter.PriceReturnData memory pData) {}


    /// @notice Helper function for pricing support for `asset`,
    ///         an lp token for a Univ2 style stable liquidity pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to add pricing support for.
    function addAsset(
        address asset,
        AdapterData memory data
    ) public virtual {

        // Make sure `asset` is not trying to price denominated in itself.
        if (asset == data.baseToken) {
            revert AerodromeAdapter__InvalidAsset();
        }

        // Save adapter data and update mapping that we support `asset` now.
        adapterData[asset] = data;
        
        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit AerodromePoolAssetAdded(asset, data, isUpdate);
    }

    /// @notice Helper function to remove a supported asset from the adapter.
    /// @dev Calls back into oracle router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adapter.
    function removeAsset(address asset) external override {
        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert AerodromeAdapter__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adapter to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adapterData[asset];

        // Notify the oracle router that we are going to stop supporting
        // the asset.
        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(asset);
    }

    
}