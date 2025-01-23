// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC20Metadata} from "../interfaces/IERC20Metadata.sol";
import {ChainlinkResponse, PriceDenomination, PriceFeedInfo, VaultReport} from "../interfaces/ISharePriceOracle.sol";
import {ChainlinkLib} from "./ChainlinkLib.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

import {console} from "forge-std/console.sol";

/// @title PriceConversionLib
/// @notice Library for converting prices between different assets using Chainlink price feeds
/// @dev Uses FixedPointMathLib for safe mathematical operations
library PriceConversionLib {
    using FixedPointMathLib for uint256;
    using ChainlinkLib for address;

    struct ConversionParams {
        uint256 amount;
        uint32 srcChainId;
        uint32 chainId;
        address srcAsset;
        address dstAsset;
        address ethUsdFeed;
        PriceFeedInfo srcFeed;
        PriceFeedInfo dstFeed;
        VaultReport srcReport;
    }

    function convertFullPrice(
        ConversionParams memory params
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get price feed responses
        ChainlinkResponse memory src = params.srcFeed.feed.getPrice();
        ChainlinkResponse memory dst = params.dstFeed.feed.getPrice();

        // Get the input amount and handle cross-chain decimals
        uint256 scaledAmount = params.amount;
        uint8 srcDecimals = params.srcChainId != params.chainId ? 
            uint8(params.srcReport.assetDecimals) : 
            IERC20Metadata(params.srcAsset).decimals();
        
        // Scale to 18 decimals if needed
        if (srcDecimals < 18) {
            scaledAmount = scaledAmount * 10 ** (18 - srcDecimals);
        }
        
        // Normalize price feeds to 18 decimals
        uint256 srcPrice = src.price;
        if (src.decimals < 18) {
            srcPrice = srcPrice * 10 ** (18 - src.decimals);
        }
        
        uint256 dstPrice = dst.price;
        if (dst.decimals < 18) {
            dstPrice = dstPrice * 10 ** (18 - dst.decimals);
        }

        uint256 minTimestamp = src.timestamp < dst.timestamp ? src.timestamp : dst.timestamp;

        // Handle USD/ETH denomination differences
        if (params.srcFeed.denomination != params.dstFeed.denomination) {
            ChainlinkResponse memory ethUsd = params.ethUsdFeed.getPrice();
            uint256 ethUsdPrice = ethUsd.price;
            
            if (ethUsd.decimals < 18) {
                ethUsdPrice = ethUsdPrice * 10 ** (18 - ethUsd.decimals);
            }

            if (params.srcFeed.denomination == PriceDenomination.ETH) {
                // Convert ETH to USD: multiply by ETH/USD price
                srcPrice = srcPrice.mulDiv(ethUsdPrice, 1e18);
            } else if (params.dstFeed.denomination == PriceDenomination.ETH) {
                // Convert USD to ETH: divide by ETH/USD price
                srcPrice = srcPrice.mulDiv(1e18, ethUsdPrice);
            }

            minTimestamp = minTimestamp < ethUsd.timestamp ? minTimestamp : ethUsd.timestamp;
        }

        // Calculate final price with all values normalized to 18 decimals
        price = scaledAmount.mulDiv(srcPrice, dstPrice);

        // Scale to destination decimals
        uint8 dstDecimals = IERC20Metadata(params.dstAsset).decimals();
        if (dstDecimals < 18) {
            price = price / 10 ** (18 - dstDecimals);
        }

        timestamp = uint64(minTimestamp);
    }

    function _normalizeDecimals(
        uint256 srcPrice,
        uint256 dstPrice,
        uint8 srcDecimals,
        uint8 dstDecimals,
        uint256 powerOfTen
    )
        internal
        pure
        returns (uint256 normalizedSrcPrice, uint256 normalizedDstPrice)
    {
        normalizedSrcPrice = srcPrice;
        normalizedDstPrice = dstPrice;

        if (srcDecimals == dstDecimals)
            return (normalizedSrcPrice, normalizedDstPrice);

        if (srcDecimals > dstDecimals) {
            normalizedSrcPrice = normalizedSrcPrice.mulDiv(1, powerOfTen);
        } else {
            normalizedDstPrice = normalizedDstPrice.mulDiv(1, powerOfTen);
        }

        return (normalizedSrcPrice, normalizedDstPrice);
    }
}
