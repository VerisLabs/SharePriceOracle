// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { CurveBaseAdapter } from "src/adapters/curve/CurveBaseAdapter.sol";
import { CommonLib } from "src/libs/CommonLib.sol";

import { ISharePriceRouter } from "../../interfaces/ISharePriceRouter.sol";
import { ICurvePool } from "../../interfaces/curve/ICurvePool.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";

/// @notice NOTE: BE CAREFUL USING THIS FEED, ALTHOUGH IT HAS MANY PROTECTIVE
///               LAYERS ITS STILL INTENDED TO BE COMBINED WITH OTHER ORACLE
///               SOLUTIONS. DO NOT USE THIS ORACLE BY ITSELF.
contract Curve2PoolAssetAdapter is CurveBaseAdapter {
    /// TYPES ///

    /// @notice Stores configuration data for Curve LP price sources.
    /// @param pool The address of the LP token/Curve pool.
    /// @param baseToken The address of asset that the adapter is trying
    ///                  to price.
    /// @param baseTokenIndex The index inside coins() corresponding
    ///                       to `baseToken`.
    /// @param quoteTokenIndex The index inside coins() corresponding
    ///                        to the asset that `baseToken` is priced in.
    /// @param baseTokenDecimals The decimals of `baseToken`.
    /// @param quoteTokenDecimals The decimals of the token at `quoteTokenIndex`.
    /// @param upperBound Upper bound allowed for an LP token's virtual price.
    /// @param lowerBound Lower bound allowed for an LP token's virtual price.
    struct AdapterData {
        address pool;
        address baseToken;
        int128 baseTokenIndex;
        int128 quoteTokenIndex;
        uint256 baseTokenDecimals;
        uint256 quoteTokenDecimals;
        uint256 upperBound;
        uint256 lowerBound;
    }

    /// CONSTANTS ///

    /// @notice Maximum bound range that can be increased on either side,
    ///         this is not meant to be anti tamperproof but,
    ///         more-so mitigate any human error.
    ///         .02e18 = 2%.
    uint256 internal constant _MAX_BOUND_INCREASE = .02e18;
    /// @notice Maximum difference between lower bound and upper bound,
    ///         checked on configuration.
    ///         .05e18 = 5%.
    uint256 internal constant _MAX_BOUND_RANGE = .05e18;

    /// STORAGE ///

    /// @notice Adapter configuration data for pricing an asset.
    /// @dev Curve asset address => AdapterData.
    mapping(address => AdapterData) public adapterData;

    ISharePriceRouter public oracleRouter;

    /// EVENTS ///

    event CurvePoolAssetAdded(
        address asset, 
        AdapterData assetConfig, 
        bool isUpdate
    );
    event CurvePoolAssetRemoved(address asset);

    /// ERRORS ///

    error Curve2PoolAssetAdapter__Reentrant();
    error Curve2PoolAssetAdapter__BoundsExceeded();
    error Curve2PoolAssetAdapter__UnsupportedPool();
    error Curve2PoolAssetAdapter__AssetIsNotSupported();
    error Curve2PoolAssetAdapter__BaseAssetIsNotSupported();
    error Curve2PoolAssetAdapter__InvalidBounds();
    error Curve2PoolAssetAdapter__InvalidAsset();
    error Curve2PoolAssetAdapter__InvalidAssetIndex();
    error Curve2PoolAssetAdapter__InvalidPoolAddress();

    /// CONSTRUCTOR ///

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter
    ) CurveBaseAdapter (_admin, _oracle, _oracleRouter) {
        oracleRouter = ISharePriceRouter(
            _oracleRouter
        );
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Sets or updates a Curve pool configuration for the reentrancy
    ///         check.
    /// @param coinsLength The number of coins (from .coinsLength) on the
    ///                    Curve pool.
    /// @param gasLimit The gas limit to be set on the check.
    function setReentrancyConfig(
        uint256 coinsLength,
        uint256 gasLimit
    ) external {
        _checkOraclePermissions();
        _setReentrancyConfig(coinsLength, gasLimit);
    }

    /// @notice Retrieves the price of `asset` from Curve's built in oracle price.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD
    ) external view override returns (ISharePriceRouter.PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert Curve2PoolAssetAdapter__AssetIsNotSupported();
        }

        AdapterData memory data = adapterData[asset];
        
        // Validate we support this pool and that this is not
        // a reeentrant call.
        if (isLocked(data.pool, 2)) {
            revert Curve2PoolAssetAdapter__Reentrant();
        }

        // Cache the curve pool.
        ICurvePool pool = ICurvePool(data.pool);
        // Make sure virtualPrice is reasonable.
        uint256 virtualPrice = pool.get_virtual_price();
        
        _enforceBounds(virtualPrice, data.lowerBound, data.upperBound);

        // Get underlying token prices.
        
        (uint256 basePrice, bool errorCode) = oracleRouter.getPrice(
            data.baseToken, inUSD
        );
        if (errorCode) {
            pData.hadError = true;
            return pData;
        }

        // take 1% of liquidity as sample
        uint256 sample = pool.balances(
            uint256(uint128(data.quoteTokenIndex))
        ) / 100;

        uint256 out = pool.get_dy(
            uint256(int256(data.quoteTokenIndex)),
            uint256(int256(data.baseTokenIndex)),
            sample
        );

        uint256 price = (out * WAD * (10 ** data.quoteTokenDecimals)) /
            sample /
            (10 ** data.baseTokenDecimals); // in base token decimals

        price = (price * basePrice) / WAD;

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(price);
    }
        

    /// @notice Adds pricing support for `asset`, an asset inside
    ///         a Curve V2 pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing support for.
    /// @param data The adapter data needed to add `asset`.
    function addAsset(address asset, AdapterData memory data) external {
        _checkOraclePermissions();

        if (!isCurvePool(data.pool)) {
            revert Curve2PoolAssetAdapter__InvalidPoolAddress();
        }

        // Make sure that the asset being added has the proper input
        // via this sanity check.
        if (isLocked(data.pool, 2)) {
            revert Curve2PoolAssetAdapter__Reentrant();
        }


        // Make sure `asset` is not trying to price denominated in itself.
        if (asset == data.baseToken) {
            revert Curve2PoolAssetAdapter__InvalidAsset();
        }

        // Validate that the upper bound is greater than the lower bound.
        if (data.lowerBound >= data.upperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        ICurvePool pool = ICurvePool(data.pool);
        // Make sure that the asset matches the pools quote token.
        if (pool.coins(uint256(uint128(data.quoteTokenIndex))) != asset) {
            revert Curve2PoolAssetAdapter__InvalidAssetIndex();
        }
        if (
            pool.coins(uint256(uint128(data.baseTokenIndex))) != data.baseToken
        ) {
            revert Curve2PoolAssetAdapter__InvalidAssetIndex();
        }

        data.quoteTokenDecimals = ERC20(asset).decimals();
        // Dynamically pull the decimals from the base token contract.
        if (CommonLib.isETH(data.baseToken)) {
            data.baseTokenDecimals = 18;
        } else {
            data.baseTokenDecimals = ERC20(data.baseToken).decimals();
        }

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        data.lowerBound = _bpToWad(data.lowerBound);
        data.upperBound = _bpToWad(data.upperBound);

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + data.lowerBound < data.upperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        // Validate we can pull a virtual price.
        uint256 testVirtualPrice = pool.get_virtual_price();

        // Validate the virtualPrice is within the desired bounds.
        _enforceBounds(testVirtualPrice, data.lowerBound, data.upperBound);

        // Save adapter data and update mapping that we support `asset` now.
        adapterData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit CurvePoolAssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adapter.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adapter.
    function removeAsset(address asset) external override {
        _checkOraclePermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert Curve2PoolAssetAdapter__AssetIsNotSupported();
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adapter to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adapterData[asset];

        // Notify the Oracle Router that we are going to stop supporting
        // the asset.
        oracleRouter.notifyFeedRemoval(asset);
        emit CurvePoolAssetRemoved(asset);
    }

    /// @notice Raises virtual price bounds for `asset`. Must be greater than
    ///         old bounds, cannot be more than `_MAX_BOUND_RANGE` apart.
    /// @dev Reverts if the new bounds are not larger than the old ones,
    ///      as virtual price should always be increasing,
    ///      barring a pool exploit.
    /// @param asset The address of the asset to update virtual price
    ///              bounds for.
    /// @param newLowerBound The new lower bound to make sure `price`
    ///                      is greater than.
    /// @param newUpperBound The new upper bound to make sure `price`
    ///                      is less than.
    function raiseBounds(
        address asset,
        uint256 newLowerBound,
        uint256 newUpperBound
    ) external {
        _checkOraclePermissions();

        // Convert the parameters from `basis points` to `WAD` form,
        // while inefficient consistently entering parameters in
        // `basis points` minimizes potential human error,
        // even if it costs a bit extra gas on configuration.
        newLowerBound = _bpToWad(newLowerBound);
        newUpperBound = _bpToWad(newUpperBound);

        AdapterData storage data = adapterData[asset];
        // Cache the old virtual price bounds.
        uint256 oldLowerBound = data.lowerBound;
        uint256 oldUpperBound = data.upperBound;

        // Validate that the upper bound is greater than the lower bound.
        if (newLowerBound >= newUpperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        // Validate that the range between bounds is not too large.
        if (_MAX_BOUND_RANGE + newLowerBound < newUpperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        // Validate that the new bounds are higher than the old ones,
        // since virtual prices only rise overtime,
        // so they should never be decreased here.
        if (newLowerBound <= oldLowerBound || newUpperBound <= oldUpperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        if (oldLowerBound + _MAX_BOUND_INCREASE < newLowerBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        if (oldUpperBound + _MAX_BOUND_INCREASE < newUpperBound) {
            revert Curve2PoolAssetAdapter__InvalidBounds();
        }

        uint256 testVirtualPrice = ICurvePool(data.pool).get_virtual_price();
        // Validate the virtualPrice is within the desired bounds.
        _enforceBounds(testVirtualPrice, newLowerBound, newUpperBound);

        data.lowerBound = newLowerBound;
        data.upperBound = newUpperBound;
    }

    /// @notice Helper function to check if `price` is within a reasonable
    ///         bound. 
    /// @dev Reverts if bounds are breached.
    /// @param virtualPrice The virtual price to check against `lowerBound`
    ///                     and `upperBound`.
    /// @param lowerBound The lower bound to make sure `price` is greater than.
    /// @param upperBound The upper bound to make sure `price` is less than.
    function _enforceBounds(
        uint256 virtualPrice,
        uint256 lowerBound,
        uint256 upperBound
    ) internal pure {
        if (virtualPrice < lowerBound || virtualPrice > upperBound) {
            revert Curve2PoolAssetAdapter__BoundsExceeded();
        }
    }

    /// @notice Multiplies `value` by 1e14 to convert it from `basis points`
    ///         to WAD.
    /// @dev Internal helper function for easily converting between scalars.
    function _bpToWad(uint256 value) internal pure returns (uint256) {
        return value * 1e14;
    }
}