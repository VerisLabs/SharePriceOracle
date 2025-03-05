// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../libs/base/BaseOracleAdapter.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ISharePriceRouter, PriceReturnData } from "../interfaces/ISharePriceRouter.sol";
import { IStaticOracle } from "../interfaces/uniswap/IStaticOracle.sol";
import { UniswapV3Pool } from "../interfaces/uniswap/UniswapV3Pool.sol";

contract UniswapV3Adapter is BaseOracleAdapter {
    /// TYPES ///

    /// @notice Stores configuration data for Uniswap V3 twap price sources.
    /// @param priceSource The address location where you query
    ///                    the associated assets twap price.
    /// @param secondsAgo Period used for twap calculation.
    /// @param baseDecimals The decimals of base asset you want to price.
    /// @param quoteDecimals The decimals asset price is quoted in.
    /// @param quoteToken The asset twap calulation denominates in.
    struct AdaptorData {
        address priceSource;
        uint32 secondsAgo;
        uint8 baseDecimals;
        uint8 quoteDecimals;
        address quoteToken;
    }

    /// CONSTANTS ///

    /// @notice The smallest possible twap that can be used.
    ///         900 = 15 minutes.
    uint32 public constant MINIMUM_SECONDS_AGO = 900;

    /// @notice Chain WETH address.
    address public immutable WETH;

    /// @notice Static uniswap Oracle Router address.
    IStaticOracle public immutable uniswapOracleRouter;

    /// STORAGE ///

    /// @notice Adaptor configuration data for pricing an asset.
    /// @dev Asset Address => AdaptorData.
    mapping(address => AdaptorData) public adaptorData;

    /// EVENTS ///

    event UniswapV3AssetAdded(address asset, AdaptorData assetConfig, bool isUpdate);
    event UniswapV3AssetRemoved(address asset);

    /// ERRORS ///

    error UniswapV3Adaptor__AssetIsNotSupported(address asset);
    error UniswapV3Adaptor__SecondsAgoIsLessThanMinimum(uint32 provided, uint32 minimum);
    error UniswapV3Adaptor__AssetNotInPool(address asset, address pool, address token0, address token1);

    /// CONSTRUCTOR ///

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter,
        IStaticOracle oracleAddress_,
        address WETH_
    )
        BaseOracleAdapter(_admin, _oracle, _oracleRouter)
    {
        uniswapOracleRouter = oracleAddress_;
        WETH = WETH_;
    }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of `asset` using a Univ3 pool.
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(address asset, bool inUSD) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert UniswapV3Adaptor__AssetIsNotSupported(asset);
        }

        AdaptorData memory data = adaptorData[asset];

        // Cache array length in memory for gas optimization
        uint256 poolLength = 1;
        address[] memory pools = new address[](poolLength);
        pools[0] = data.priceSource;
        uint256 twapPrice;

        // Pull twap price via a staticcall.
        (bool success, bytes memory returnData) = address(uniswapOracleRouter).staticcall(
            abi.encodePacked(
                uniswapOracleRouter.quoteSpecificPoolsWithTimePeriod.selector,
                abi.encode(10 ** data.baseDecimals, asset, data.quoteToken, pools, data.secondsAgo)
            )
        );

        if (success) {
            // Extract the twap price from returned calldata.
            twapPrice = abi.decode(returnData, (uint256));
        } else {
            // Uniswap twap check reverted, bubble up an error.
            pData.hadError = true;
            return pData;
        }

        ISharePriceRouter OracleRouter = ISharePriceRouter(ORACLE_ROUTER_ADDRESS);
        pData.inUSD = inUSD;

        // We want the asset price in USD which uniswap cant do,
        // so find out the price of the quote token in USD then divide
        // so its in USD.
        if (inUSD) {
            if (!OracleRouter.isSupportedAsset(data.quoteToken)) {
                // Our Oracle Router does not know how to value this quote
                // token, so, we cant use the twap data, bubble up an error.
                pData.hadError = true;
                return pData;
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = OracleRouter.getPrice(data.quoteToken, true);

            // Validate we did not run into any errors pricing the quote asset.
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            // We have a route to USD pricing so we can convert
            // the quote token price to USD and return.
            uint256 newPrice = (twapPrice * quoteTokenDenominator) / (10 ** data.quoteDecimals);

            // Validate price will not overflow on conversion to uint240.
            if (_checkOracleOverflow(newPrice)) {
                pData.hadError = true;
                return pData;
            }

            pData.price = uint240(newPrice);
            return pData;
        }

        if (data.quoteToken != WETH) {
            if (!OracleRouter.isSupportedAsset(data.quoteToken)) {
                // Our Oracle Router does not know how to value this quote
                // token so we cant use the twap data.
                pData.hadError = true;
                return pData;
            }

            (uint256 quoteTokenDenominator, uint256 errorCode) = OracleRouter.getPrice(data.quoteToken, false);

            // Validate we did not run into any errors pricing the quote asset.
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            // Adjust decimals if necessary.
            uint256 newPrice = (twapPrice * quoteTokenDenominator) / (10 ** data.quoteDecimals);

            // Validate price will not overflow on conversion to uint240.
            if (_checkOracleOverflow(newPrice)) {
                pData.hadError = true;
                return pData;
            }

            // We have a route to ETH pricing so we can convert
            // the quote token price to ETH and return.
            pData.price = uint240(newPrice);
            return pData;
        }

        // Validate price will not overflow on conversion to uint240.
        if (_checkOracleOverflow(twapPrice)) {
            pData.hadError = true;
            return pData;
        }

        pData.price = uint240(twapPrice);
    }

    /// @notice Adds pricing support for `asset`, a token inside a Univ3 lp.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the token to add pricing support for.
    /// @param data The adaptor data needed to add `asset`.
    function addAsset(address asset, AdaptorData memory data) external {
        _checkOraclePermissions();

        // Verify twap time sample is reasonable.
        if (data.secondsAgo < MINIMUM_SECONDS_AGO) {
            revert UniswapV3Adaptor__SecondsAgoIsLessThanMinimum(data.secondsAgo, MINIMUM_SECONDS_AGO);
        }

        UniswapV3Pool pool = UniswapV3Pool(data.priceSource);

        // Query tokens from pool directly to minimize misconfiguration.
        address token0 = pool.token0();
        address token1 = pool.token1();
        if (token0 == asset) {
            data.baseDecimals = ERC20(asset).decimals();
            data.quoteDecimals = ERC20(token1).decimals();
            data.quoteToken = token1;
        } else if (token1 == asset) {
            data.baseDecimals = ERC20(asset).decimals();
            data.quoteDecimals = ERC20(token0).decimals();
            data.quoteToken = token0;
        } else {
            revert UniswapV3Adaptor__AssetNotInPool(asset, data.priceSource, token0, token1);
        }

        // Save adaptor data and update mapping that we support `asset` now.
        adaptorData[asset] = data;

        // Check whether this is new or updated support for `asset`.
        bool isUpdate;
        if (isSupportedAsset[asset]) {
            isUpdate = true;
        }

        isSupportedAsset[asset] = true;
        emit UniswapV3AssetAdded(asset, data, isUpdate);
    }

    /// @notice Removes a supported asset from the adaptor.
    /// @dev Calls back into Oracle Router to notify it of its removal.
    ///      Requires that `asset` is currently supported.
    /// @param asset The address of the supported asset to remove from
    ///              the adaptor.
    function removeAsset(address asset) external override {
        _checkOraclePermissions();

        // Validate that `asset` is currently supported.
        if (!isSupportedAsset[asset]) {
            revert UniswapV3Adaptor__AssetIsNotSupported(asset);
        }

        // Wipe config mapping entries for a gas refund.
        // Notify the adaptor to stop supporting the asset.
        delete isSupportedAsset[asset];
        delete adaptorData[asset];

        // Notify the Oracle Router that we are going
        // to stop supporting the asset.
        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(asset);
        emit UniswapV3AssetRemoved(asset);
    }
}
