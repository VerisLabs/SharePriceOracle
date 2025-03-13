// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../libs/base/BaseOracleAdapter.sol";
import { ISharePriceRouter } from "../interfaces/ISharePriceRouter.sol";
import { IRedstone } from "../interfaces/redstone/IRedstone.sol";

/**
 * @title RedStoneAdapter
 * @notice Adapter contract for fetching and normalizing price data from RedStone oracles
 * @dev Handles both USD and ETH denominated price feeds from RedStone
 */
contract RedStoneAdapter is BaseOracleAdapter {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Configuration data for RedStone price sources
    /// @param aggregator Redstone aggregator address for price feed
    /// @param isConfigured Whether asset is configured (false = unconfigured, true = configured)
    /// @param decimals Number of decimals in aggregator response
    /// @param heartbeat Maximum time between price updates (0 = DEFAULT_HEART_BEAT)
    /// @param max Maximum valid price (0 = proxy max price reduced by ~10%)
    /// @param min Minimum valid price (0 = proxy min price increased by ~10%)
    struct AdapterData {
        IRedstone aggregator;
        bool isConfigured;
        uint256 decimals;
        uint256 heartbeat;
        uint256 max;
        uint256 min;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Default heartbeat duration if none specified
    /// @dev 1 days = 24 hours = 1,440 minutes = 86,400 seconds
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of asset addresses to their ETH-denominated price feed data
    mapping(address => AdapterData) public adaptorDataNonUSD;

    /// @notice Mapping of asset addresses to their USD-denominated price feed data
    mapping(address => AdapterData) public adaptorDataUSD;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RedStoneAssetAdded(address asset, AdapterData assetConfig, bool isUpdate);
    event RedStoneAssetRemoved(address asset);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error RedStoneAdaptor__AssetNotSupported();
    error RedStoneAdaptor__InvalidHeartbeat();
    error RedStoneAdaptor__InvalidMinMaxConfig();
    error RedStoneAdaptor__SequencerDown();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter
    )
        BaseOracleAdapter(_admin, _oracle, _oracleRouter)
    { }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the price of a specified asset from RedStone
     * @param asset Address of the asset to price
     * @param inUSD Whether to return the price in USD (true) or ETH (false)
     * @return ISharePriceRouter.PriceReturnData Structure containing price, error status, and denomination
     */
    function getPrice(
        address asset,
        bool inUSD
    )
        external
        view
        override
        returns (ISharePriceRouter.PriceReturnData memory)
    {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert RedStoneAdaptor__AssetNotSupported();
        }

        // Check whether we want the pricing in USD first,
        // otherwise price in terms of the gas token.
        if (inUSD) {
            return _getPriceInUSD(asset);
        }

        return _getPriceInETH(asset);
    }

    /**
     * @notice Adds or updates a RedStone price feed for an asset
     * @param asset Address of the token to configure
     * @param aggregator Address of the RedStone aggregator
     * @param heartbeat Maximum allowed time between updates (0 = DEFAULT_HEART_BEAT)
     * @param inUSD Whether feed provides USD prices (true) or ETH prices (false)
     */
    function addAsset(address asset, address aggregator, uint256 heartbeat, bool inUSD) external {
        _checkOraclePermissions();

        if (heartbeat != 0) {
            if (heartbeat > DEFAULT_HEART_BEAT) {
                revert RedStoneAdaptor__InvalidHeartbeat();
            }
        }

        // Use RedStone to get the min and max of the asset.
        IRedstone feedAggregator = IRedstone(IRedstone(aggregator).aggregator());

        // Query Max and Min feed prices from RedStone aggregator.
        uint256 maxFromRedstone = uint256(uint192(feedAggregator.maxAnswer()));
        uint256 minFromRedstone = uint256(uint192(feedAggregator.minAnswer()));

        // Add a ~10% buffer to minimum and maximum price from RedStone
        // because RedStone can stop updating its price before/above
        // the min/max price.
        uint256 bufferedMaxPrice = (maxFromRedstone * 9) / 10;
        uint256 bufferedMinPrice = (minFromRedstone * 11) / 10;

        // If the buffered max price is above uint240 its theoretically
        // possible to get a price which would lose precision on uint240
        // conversion, which we need to protect against in getPrice() so
        // we can add a second protective layer here.
        if (bufferedMaxPrice > type(uint240).max) {
            bufferedMaxPrice = type(uint240).max;
        }

        if (bufferedMinPrice >= bufferedMaxPrice) {
            revert RedStoneAdaptor__InvalidMinMaxConfig();
        }

        AdapterData storage data;

        if (inUSD) {
            data = adaptorDataUSD[asset];
        } else {
            data = adaptorDataNonUSD[asset];
        }

        // Save adaptor data and update mapping that we support `asset` now.
        data.decimals = feedAggregator.decimals();
        data.max = bufferedMaxPrice;
        data.min = bufferedMinPrice;
        data.heartbeat = heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT;
        data.aggregator = IRedstone(aggregator);
        data.isConfigured = true;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit RedStoneAssetAdded(asset, data, isUpdate);
    }

    /**
     * @notice Removes price feed support for an asset
     * @dev Calls back into Oracle Router to notify it of its removal
     * @param asset Address of the asset to remove
     */
    function removeAsset(address asset) external override {
        _checkOraclePermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert RedStoneAdaptor__AssetNotSupported();
        }

        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];

        // Wipe config mapping entries for a gas refund.
        delete adaptorDataUSD[asset];
        delete adaptorDataNonUSD[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(asset);
        emit RedStoneAssetRemoved(asset);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the price of a specified asset in USD
     * @param asset Address of the asset to price
     * @return ISharePriceRouter.PriceReturnData Structure containing price, error status, and denomination in USD
     */
    function _getPriceInUSD(address asset) internal view returns (ISharePriceRouter.PriceReturnData memory) {
        if (adaptorDataUSD[asset].isConfigured) {
            return _parseData(adaptorDataUSD[asset], true);
        }

        return _parseData(adaptorDataNonUSD[asset], false);
    }

    /**
     * @notice Retrieves the price of a specified asset in ETH
     * @param asset Address of the asset to price
     * @return ISharePriceRouter.PriceReturnData Structure containing price, error status, and denomination in ETH
     */
    function _getPriceInETH(address asset) internal view returns (ISharePriceRouter.PriceReturnData memory) {
        if (adaptorDataNonUSD[asset].isConfigured) {
            return _parseData(adaptorDataNonUSD[asset], false);
        }

        return _parseData(adaptorDataUSD[asset], true);
    }

    /**
     * @notice Parses raw RedStone price feed data
     * @dev Normalizes decimals to WAD and validates price data
     * @param data Adapter configuration data for the price feed
     * @param inUSD Whether price is in USD (true) or ETH (false)
     * @return pData Structure containing normalized price and status
     */
    function _parseData(
        AdapterData memory data,
        bool inUSD
    )
        internal
        view
        returns (ISharePriceRouter.PriceReturnData memory pData)
    {
        pData.inUSD = inUSD;
        if (!ISharePriceRouter(ORACLE_ROUTER_ADDRESS).isSequencerValid()) {
            revert RedStoneAdaptor__SequencerDown();
        }

        (, int256 price,, uint256 updatedAt,) = IRedstone(data.aggregator).latestRoundData();

        // If we got a price of 0 or less, bubble up an error immediately.
        if (price <= 0) {
            pData.hadError = true;
            return pData;
        }

        uint256 newPrice = (uint256(price) * WAD) / (10 ** data.decimals);

        pData.price = uint240(newPrice);
        pData.hadError = _verifyData(uint256(price), updatedAt, data.max, data.min, data.heartbeat);
    }

    /**
     * @notice Validates RedStone feed data against configured constraints
     * @dev Checks value bounds and staleness against heartbeat
     * @param value Current price value from feed
     * @param timestamp Last update timestamp
     * @param max Maximum allowed price
     * @param min Minimum allowed price
     * @param heartbeat Maximum allowed time between updates
     * @return bool True if feed data had an error, false otherwise
     */
    function _verifyData(
        uint256 value,
        uint256 timestamp,
        uint256 max,
        uint256 min,
        uint256 heartbeat
    )
        internal
        view
        returns (bool)
    {
        // Validate `value` is not below the buffered min value allowed.
        if (value < min) {
            return true;
        }

        // Validate `value` is not above the buffered maximum value allowed.
        if (value > max) {
            return true;
        }

        // Validate the price returned is not stale.
        if (block.timestamp - timestamp > heartbeat) {
            return true;
        }

        return false;
    }
}