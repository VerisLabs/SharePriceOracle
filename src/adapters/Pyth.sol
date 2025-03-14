// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../libs/base/BaseOracleAdapter.sol";
import { ISharePriceRouter } from "../interfaces/ISharePriceRouter.sol";
import "../interfaces/pyth/IPyth.sol";
import "../interfaces/pyth/PythStructs.sol";
import "../interfaces/pyth/PythUtils.sol";

/**
 * @title PythAdapter
 * @notice Oracle adapter for Pyth Network price feeds
 * @dev Provides price data from Pyth Network to the SharePriceRouter
 */
contract PythAdapter is BaseOracleAdapter {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Configuration data for Pyth price sources
    /// @param priceId Pyth price feed ID
    /// @param isConfigured Whether the asset is configured
    /// @param heartbeat Maximum time between price updates
    /// @param maxAge Maximum age of prices to consider valid
    struct AdapterData {
        bytes32 priceId;
        bool isConfigured;
        uint32 heartbeat;
        uint32 maxAge;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Default heartbeat duration if none specified (1 day)
    uint32 public constant DEFAULT_HEARTBEAT = 86400;

    /// @notice Default maximum age for prices (60 seconds)
    uint32 public constant DEFAULT_MAX_AGE = 60;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The Pyth Network contract
    IPyth public immutable pyth;

    /// @notice Mapping of asset addresses to their USD price feed configuration
    mapping(address => AdapterData) public adapterDataUSD;

    /// @notice Mapping of asset addresses to their ETH price feed configuration
    mapping(address => AdapterData) public adapterDataETH;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PythAssetAdded(address asset, AdapterData assetConfig, bool isUpdate);
    event PythAssetRemoved(address asset);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error PythAdapter__AssetNotSupported(address asset);
    error PythAdapter__InvalidHeartbeat(uint32 heartbeat);
    error PythAdapter__InvalidMaxAge(uint32 maxAge);
    error PythAdapter__PriceUpdateFailed();
    error PythAdapter__PriceNotAvailable();
    error PythAdapter__StalePrice(uint64 publishTime, uint32 maxAge);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the PythAdapter
     * @param _admin Address that will have admin privileges
     * @param _oracle Address that will have oracle privileges
     * @param _oracleRouter Address of the Oracle Router contract
     * @param _pyth Address of the Pyth contract
     */
    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter,
        address _pyth
    )
        BaseOracleAdapter(_admin, _oracle, _oracleRouter)
    {
        pyth = IPyth(_pyth);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the price of a specified asset from Pyth
     * @param asset Address of the asset to price
     * @param inUSD Whether to return the price in USD (true) or ETH (false)
     * @return pData Structure containing price, error status, and denomination
     */
    function getPrice(
        address asset,
        bool inUSD
    )
        external
        view
        override
        returns (ISharePriceRouter.PriceReturnData memory pData)
    {
        // Validate we support pricing `asset`
        if (!isSupportedAsset[asset]) {
            revert PythAdapter__AssetNotSupported(asset);
        }

        // Check whether we want the pricing in USD first,
        // otherwise price in terms of ETH
        if (inUSD) {
            return _getPythPrice(asset, true);
        }

        return _getPythPrice(asset, false);
    }

    /**
     * @notice Updates price feeds and retrieves the price of an asset
     * @param asset Address of the asset to price
     * @param inUSD Whether to return the price in USD (true) or ETH (false)
     * @param updateData Pyth price update data
     * @return pData Structure containing price, error status, and denomination
     */
    function updateAndGetPrice(
        address asset,
        bool inUSD,
        bytes[] calldata updateData
    )
        external
        payable
        returns (ISharePriceRouter.PriceReturnData memory pData)
    {
        // Validate we support pricing `asset`
        if (!isSupportedAsset[asset]) {
            revert PythAdapter__AssetNotSupported(asset);
        }

        // Update the Pyth price feeds
        _updatePriceFeeds(updateData);

        // Get the price in the requested denomination
        if (inUSD) {
            return _getPythPrice(asset, true);
        }

        return _getPythPrice(asset, false);
    }

    /**
     * @notice Adds pricing support for an asset using Pyth price feeds
     * @param asset Address of the token to add pricing support for
     * @param priceId Pyth price feed ID
     * @param heartbeat Maximum period between price updates (0 = DEFAULT_HEARTBEAT)
     * @param maxAge Maximum age of prices to consider valid (0 = DEFAULT_MAX_AGE)
     * @param inUSD Whether feed provides USD prices (true) or ETH prices (false)
     */
    function addAsset(
        address asset,
        bytes32 priceId,
        uint32 heartbeat,
        uint32 maxAge,
        bool inUSD
    )
        external
    {
        _checkOraclePermissions();

        // Validate inputs
        if (heartbeat != 0) {
            if (heartbeat > DEFAULT_HEARTBEAT) {
                revert PythAdapter__InvalidHeartbeat(heartbeat);
            }
        }

        if (maxAge != 0) {
            if (maxAge > DEFAULT_MAX_AGE) {
                revert PythAdapter__InvalidMaxAge(maxAge);
            }
        }

        // Set up adapter data
        AdapterData storage data = inUSD ? adapterDataUSD[asset] : adapterDataETH[asset];

        data.priceId = priceId;
        data.heartbeat = heartbeat == 0 ? DEFAULT_HEARTBEAT : heartbeat;
        data.maxAge = maxAge == 0 ? DEFAULT_MAX_AGE : maxAge;
        data.isConfigured = true;

        // Check whether this is new or updated support for `asset`
        bool isUpdate = isSupportedAsset[asset];
        isSupportedAsset[asset] = true;

        emit PythAssetAdded(asset, data, isUpdate);
    }

    /**
     * @notice Removes price feed support for an asset
     * @dev Calls back into Oracle Router to notify it of its removal
     * @param asset Address of the asset to remove
     */
    function removeAsset(address asset) external override {
        _checkOraclePermissions();

        // Validate that `asset` is currently supported
        if (!isSupportedAsset[asset]) {
            revert PythAdapter__AssetNotSupported(asset);
        }

        // Wipe config mapping entries for a gas refund
        delete isSupportedAsset[asset];
        delete adapterDataUSD[asset];
        delete adapterDataETH[asset];

        // Notify the Oracle Router that we are going to stop supporting the asset
        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(asset);
        
        emit PythAssetRemoved(asset);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the price of an asset from Pyth
     * @param asset Address of the asset to price
     * @param inUSD Whether to return the price in USD
     * @return pData Structure containing price data and status
     */
    function _getPythPrice(
        address asset,
        bool inUSD
    )
        internal
        view
        returns (ISharePriceRouter.PriceReturnData memory pData)
    {
        pData.inUSD = inUSD;
        
        // Get the appropriate adapter data
        AdapterData memory data = inUSD ? adapterDataUSD[asset] : adapterDataETH[asset];
        
        // If not configured for this price type, try the other one
        if (!data.isConfigured) {
            data = inUSD ? adapterDataETH[asset] : adapterDataUSD[asset];
            pData.inUSD = !inUSD;
            
            // If neither is configured, return an error
            if (!data.isConfigured) {
                pData.hadError = true;
                return pData;
            }
        }
        
        try pyth.getPriceNoOlderThan(data.priceId, data.maxAge) returns (PythStructs.Price memory price) {
            // Validate price
            if (price.price <= 0) {
                pData.hadError = true;
                return pData;
            }
            
            // Check staleness
            if (block.timestamp - price.publishTime > data.heartbeat) {
                pData.hadError = true;
                return pData;
            }
            
            // Convert price to WAD (18 decimals)
            uint256 normalizedPrice = PythUtils.convertToUint(price.price, price.expo, 18);
            
            // Check for overflow before casting to uint240
            if (_checkOracleOverflow(normalizedPrice)) {
                pData.hadError = true;
                return pData;
            }
            
            pData.price = uint240(normalizedPrice);
            return pData;
        } catch {
            // If price retrieval fails, return an error
            pData.hadError = true;
            return pData;
        }
    }

    /**
     * @notice Updates Pyth price feeds with the provided update data
     * @param updateData The Pyth price update data
     */
    function _updatePriceFeeds(bytes[] calldata updateData) internal {
        if (updateData.length == 0) {
            return;
        }
        
        uint256 updateFee = pyth.getUpdateFee(updateData);
        pyth.updatePriceFeeds{value: updateFee}(updateData);

        
    }

    /**
     * @notice Receive function to accept ETH for price feed updates
     */
    receive() external payable {}
}