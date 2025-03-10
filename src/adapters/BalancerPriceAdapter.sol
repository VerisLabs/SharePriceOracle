// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../libs/base/BaseOracleAdapter.sol";
import { ISharePriceRouter } from "../interfaces/ISharePriceRouter.sol";
import { IERC20Metadata } from "../interfaces/IERC20Metadata.sol";
import { IBalancerV2Vault } from "../interfaces/balancer/IBalancerV2Vault.sol";
import { IBalancerV2WeightedPool } from "../interfaces/balancer/IBalancerV2WeightedPool.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/**
 * @title BalancerPriceAdapter
 * @notice Extracts asset prices from Balancer V2 weighted pools
 * @dev Provides price data from Balancer pools to the SharePriceRouter
 */
contract BalancerPriceAdapter is BaseOracleAdapter {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Configuration data for Balancer price sources
    /// @param poolId Balancer pool ID
    /// @param isConfigured Whether asset is configured
    /// @param quoteToken The token to express the price in (e.g., USDC, WETH)
    /// @param heartbeat Maximum time between price updates
    struct AdapterData {
        bytes32 poolId;
        bool isConfigured;
        address quoteToken;
        uint256 heartbeat;
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

    /// @notice Balancer V2 Vault contract
    IBalancerV2Vault public immutable balancerVault;

    /// @notice Mapping of asset addresses to their Balancer pool data
    mapping(address => AdapterData) public adapterDataUSD;
    
    /// @notice Mapping of asset addresses to their ETH pool data
    mapping(address => AdapterData) public adapterDataETH;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BalancerAssetAdded(address asset, AdapterData assetConfig, bool isUpdate);
    event BalancerAssetRemoved(address asset);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BalancerAdapter__AssetNotSupported();
    error BalancerAdapter__InvalidHeartbeat();
    error BalancerAdapter__TokensNotInPool();
    error BalancerAdapter__StalePrice();
    error BalancerAdapter__InvalidPrice();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the BalancerPriceAdapter
     * @param _admin Address that will have admin privileges
     * @param _oracle Address that will have oracle privileges
     * @param _oracleRouter Address of the Oracle Router contract
     * @param _balancerVault Address of the Balancer V2 Vault
     */
    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter,
        address _balancerVault
    )
        BaseOracleAdapter(_admin, _oracle, _oracleRouter)
    {
        if (_balancerVault == address(0)) revert ZeroAddress();
        balancerVault = IBalancerV2Vault(_balancerVault);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the price of a specified asset from Balancer
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
        // Validate we support pricing `asset`
        if (!isSupportedAsset[asset]) {
            revert BalancerAdapter__AssetNotSupported();
        }

        // Check whether we want the pricing in USD first,
        // otherwise price in terms of ETH (or the gas token)
        if (inUSD) {
            return _getPriceFromBalancer(asset, true);
        }

        return _getPriceFromBalancer(asset, false);
    }

    /**
     * @notice Adds or updates a Balancer pool for an asset
     * @param asset Address of the token to configure
     * @param poolId Balancer pool ID
     * @param quoteToken Token to express the price in (e.g., USDC or WETH)
     * @param heartbeat Maximum allowed time between updates (0 = DEFAULT_HEART_BEAT)
     * @param inUSD Whether the quote token is a USD stablecoin
     */
    function addAsset(
        address asset,
        bytes32 poolId,
        address quoteToken,
        uint256 heartbeat,
        bool inUSD
    )
        external
    {
        _checkOraclePermissions();

        // Validate inputs
        if (asset == address(0) || quoteToken == address(0)) revert ZeroAddress();
        
        if (heartbeat != 0) {
            if (heartbeat > DEFAULT_HEART_BEAT) {
                revert BalancerAdapter__InvalidHeartbeat();
            }
        }

        // Verify tokens are in the pool
        (address[] memory tokens,,) = balancerVault.getPoolTokens(poolId);
        
        bool foundAsset = false;
        bool foundQuote = false;
        
        for (uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] == asset) foundAsset = true;
            if (tokens[i] == quoteToken) foundQuote = true;
        }
        
        if (!foundAsset || !foundQuote) {
            revert BalancerAdapter__TokensNotInPool();
        }

        // Select the appropriate storage based on inUSD flag
        AdapterData storage data = inUSD ? adapterDataUSD[asset] : adapterDataETH[asset];

        // Store configuration
        data.poolId = poolId;
        data.quoteToken = quoteToken;
        data.heartbeat = heartbeat == 0 ? DEFAULT_HEART_BEAT : heartbeat;
        data.isConfigured = true;

        // Update support status
        bool isUpdate = isSupportedAsset[asset];
        isSupportedAsset[asset] = true;

        emit BalancerAssetAdded(asset, data, isUpdate);
    }

    /**
     * @notice Removes price feed support for an asset
     * @dev Calls back into Oracle Router to notify it of removal
     * @param asset Address of the asset to remove
     */
    function removeAsset(address asset) external override {
        _checkOraclePermissions();

        if (!isSupportedAsset[asset]) {
            revert BalancerAdapter__AssetNotSupported();
        }

        // Clear asset support
        delete isSupportedAsset[asset];
        delete adapterDataUSD[asset];
        delete adapterDataETH[asset];

        // Notify the Oracle Router
        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(asset);
        emit BalancerAssetRemoved(asset);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the price from a Balancer pool
     * @param asset The asset to price
     * @param inUSD Whether to price in USD or ETH
     * @return pData Price data structure
     */
    function _getPriceFromBalancer(
        address asset,
        bool inUSD
    )
        internal
        view
        returns (ISharePriceRouter.PriceReturnData memory pData)
    {
        // Initialize return data
        pData.inUSD = inUSD;
        
        // Get the appropriate config based on USD flag
        AdapterData memory config = inUSD ? adapterDataUSD[asset] : adapterDataETH[asset];
        
        // If not configured for this price type, try the other one
        if (!config.isConfigured) {
            config = inUSD ? adapterDataETH[asset] : adapterDataUSD[asset];
            pData.inUSD = !inUSD;
        }
        
        // Get pool data
        (address poolAddress,) = balancerVault.getPool(config.poolId);
        IBalancerV2WeightedPool pool = IBalancerV2WeightedPool(poolAddress);
        
        // Get pool tokens and balances
        (address[] memory tokens, uint256[] memory balances,) = balancerVault.getPoolTokens(config.poolId);
        
        // Find indices of asset and quote token
        uint8 assetIndex = type(uint8).max;
        uint8 quoteIndex = type(uint8).max;
        
        for (uint8 i = 0; i < tokens.length; i++) {
            if (tokens[i] == asset) assetIndex = i;
            if (tokens[i] == config.quoteToken) quoteIndex = i;
        }
        
        if (assetIndex == type(uint8).max || quoteIndex == type(uint8).max) {
            pData.hadError = true;
            return pData;
        }
        
        // Get normalized weights
        uint256[] memory weights = pool.getNormalizedWeights();
        
        // Get token decimals for proper scaling
        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        uint8 quoteDecimals = IERC20Metadata(config.quoteToken).decimals();
        
        // Calculate the price with 18 decimals precision
        // For weighted pools, the spot price is: spotPrice = (balanceQuote / weightQuote) / (balanceAsset / weightAsset)
        uint256 price = _calculatePrice(
            balances[quoteIndex],
            balances[assetIndex],
            weights[quoteIndex],
            weights[assetIndex],
            assetDecimals,
            quoteDecimals
        );
        
        // Check pool staleness using the lastChangeBlock from getPoolTokens
        // This is a simplification - in production, you might want to track timestamps more precisely
        (,,uint256 lastChangeBlock) = balancerVault.getPoolTokens(config.poolId);
        
        // Convert blocks to approximate time (assuming ~12 second blocks)
        uint256 blockTimeDiff = block.number - lastChangeBlock;
        uint256 approxTimeDiff = blockTimeDiff * 12;
        
        if (approxTimeDiff > config.heartbeat) {
            pData.hadError = true;
            return pData;
        }
        
        // Validate price
        if (price == 0) {
            pData.hadError = true;
            return pData;
        }
        
        // Check for overflow before casting to uint240
        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }
        
        pData.price = uint240(price);
        return pData;
    }

    /**
     * @notice Calculates price from pool data
     * @param quoteBalance Balance of quote token in pool
     * @param assetBalance Balance of asset token in pool
     * @param quoteWeight Weight of quote token in pool
     * @param assetWeight Weight of asset token in pool
     * @param assetDecimals Decimals of asset token
     * @param quoteDecimals Decimals of quote token
     * @return price Calculated price with 18 decimals precision
     */
    function _calculatePrice(
        uint256 quoteBalance,
        uint256 assetBalance,
        uint256 quoteWeight,
        uint256 assetWeight,
        uint8 assetDecimals,
        uint8 quoteDecimals
    )
        internal
        pure
        returns (uint256 price)
    {
        if (assetBalance == 0 || quoteWeight == 0 || assetWeight == 0) {
            return 0;
        }
        
        // For weighted pools, the spot price is:
        // spotPrice = (balanceQuote / weightQuote) / (balanceAsset / weightAsset)
        uint256 numerator = quoteBalance * assetWeight;
        uint256 denominator = assetBalance * quoteWeight;
        
        // Apply decimal adjustment for 18 decimal precision
        uint256 decimalAdjustment = 10**(18 + assetDecimals - quoteDecimals);
        
        // Use FixedPointMathLib for safer math operations
        price = FixedPointMathLib.mulDiv(numerator, decimalAdjustment, denominator);
        
        return price;
    }
}