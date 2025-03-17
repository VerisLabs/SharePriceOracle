// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { AerodromeBaseAdapter } from "./AerodromeBaseAdapter.sol";
import { ISharePriceOracle } from "../../interfaces/ISharePriceOracle.sol";
import { IAerodromeV2Pool } from "../../interfaces/aerodrome/IAerodromeV2Pool.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

contract AerodromeV2Adapter is AerodromeBaseAdapter {
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for uint160;

    /// CONSTRUCTOR ///

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter
    )
        AerodromeBaseAdapter(_admin, _oracle, _oracleRouter)
    { }

    /// EXTERNAL FUNCTIONS ///

    /// @notice Retrieves the price of `asset` from Aerodrom pool
    /// @dev Price is returned in USD or ETH depending on 'inUSD' parameter.
    /// @param asset The address of the asset for which the price is needed.
    /// @param inUSD A boolean to determine if the price should be returned in
    ///              USD or not.
    /// @return pData A structure containing the price, error status,
    ///                         and the quote format of the price.
    function getPrice(
        address asset,
        bool inUSD
    )
        external
        view
        virtual
        override
        returns (ISharePriceOracle.PriceReturnData memory pData)
    {
        // Validate we support pricing `asset`.
        if (!isSupportedAsset[asset]) {
            revert AerodromeAdapter__AssetIsNotSupported();
        }

        AdapterData memory data = adapterData[asset];

        // Get underlying token prices.

        (uint256 basePrice, bool errorCode) = oracleRouter.getPrice(data.baseToken, inUSD);
        if (errorCode) {
            pData.hadError = true;
            return pData;
        }

        (uint160 sqrtPriceX96,,,,,) = IAerodromeV2Pool(data.pool).slot0();

        //  Convert sqrtPriceX96 to sqrtPrice
        uint256 sqrtPrice = sqrtPriceX96.fullMulDiv(1e18, 2 ** 96);
        // Compute token0 per token1 (price ratio)
        uint256 price_token0_per_token1 = sqrtPrice.fullMulDiv(sqrtPrice, 1e18);

        // Compute token1 per token0
        uint256 price_token1_per_token0 = uint256(1e18).fullMulDiv(1e18, price_token0_per_token1);

        uint256 scaleFactor = data.quoteTokenDecimals > data.baseTokenDecimals
            ? 10 ** (data.quoteTokenDecimals - data.baseTokenDecimals)
            : 1e18 / (10 ** (data.baseTokenDecimals - data.quoteTokenDecimals));

        uint256 price = price_token1_per_token0 * scaleFactor;
        price = (price * basePrice) / WAD;

        if (_checkOracleOverflow(price)) {
            pData.hadError = true;
            return pData;
        }

        pData.inUSD = inUSD;
        pData.price = uint240(price);
    }

    /// @notice Helper function for pricing support for `asset`,
    ///         an lp token for a Univ2 style stable liquidity pool.
    /// @dev Should be called before `OracleRouter:addAssetPriceFeed`
    ///      is called.
    /// @param asset The address of the lp token to add pricing support for.
    function addAsset(address asset, AdapterData memory data) public override {
        _checkOraclePermissions();

        if (!isAeroPool(data.pool)) {
            revert AerodromeAdapter__InvalidPoolAddress();
        }

        super.addAsset(asset, data);
    }

    function isAeroPool(address pool) public view returns (bool) {
        try IAerodromeV2Pool(pool).token0() returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
