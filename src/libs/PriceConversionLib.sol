// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC20Metadata} from "../interfaces/IERC20Metadata.sol";
import {ChainlinkResponse, PriceDenomination, PriceFeedInfo, VaultReport} from "../interfaces/ISharePriceOracle.sol";
import {ChainlinkLib} from "./ChainlinkLib.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title Price Conversion Library
/// @notice Handles price conversions between different assets using Chainlink price feeds
/// @dev All calculations are done in 18 decimals first, then adjusted to target decimals
library PriceConversionLib {
    using FixedPointMathLib for uint256;
    using ChainlinkLib for address;

    // Standard scaling factor for 18 decimal precision
    uint256 private constant SCALE = 1e18;

    struct ConversionParams {
        uint256 amount;          // Amount to convert
        uint32 srcChainId;       // Source chain ID
        uint32 chainId;          // Destination chain ID
        address srcAsset;        // Source asset address
        address dstAsset;        // Destination asset address
        address ethUsdFeed;      // ETH/USD price feed
        PriceFeedInfo srcFeed;   // Source asset price feed
        PriceFeedInfo dstFeed;   // Destination asset price feed
        VaultReport srcReport;   // Source vault report
    }

    /// @notice Converts amount from source asset to destination asset price
    /// @dev Process:
    /// 1. Get prices from Chainlink feeds
    /// 2. Normalize all prices to 18 decimals
    /// 3. Convert between USD/ETH denomination if needed
    /// 4. Calculate final price considering all decimal adjustments
    function convertFullPrice(
        ConversionParams memory params
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Step 1: Get base prices from Chainlink
        ChainlinkResponse memory src = params.srcFeed.feed.getPrice();
        ChainlinkResponse memory dst = params.dstFeed.feed.getPrice();
        if (src.price == 0 || dst.price == 0) return (0, 0);

        // Step 2: Get asset decimals - handle cross-chain case differently
        uint8 srcDecimals = params.srcChainId != params.chainId ? 
            uint8(params.srcReport.assetDecimals) : 
            IERC20Metadata(params.srcAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(params.dstAsset).decimals();

        unchecked {
            // Step 3: Normalize Chainlink prices to 18 decimals
            // Example: If Chainlink returns 8 decimals, multiply by 10^(18-8) = 10^10
            uint256 srcAdjust = src.decimals < 18 ? SCALE / (10 ** src.decimals) : 1;
            uint256 dstAdjust = dst.decimals < 18 ? SCALE / (10 ** dst.decimals) : 1;
            uint256 srcPrice = src.price * srcAdjust;
            uint256 dstPrice = dst.price * dstAdjust;

            // Track earliest timestamp for price freshness
            timestamp = uint64(src.timestamp < dst.timestamp ? src.timestamp : dst.timestamp);
            
            // Step 4: Handle USD/ETH denomination difference
            if (params.srcFeed.denomination != params.dstFeed.denomination) {
                ChainlinkResponse memory ethUsd = params.ethUsdFeed.getPrice();
                if (ethUsd.price == 0) return (0, 0);
                
                // Normalize ETH/USD price to 18 decimals
                uint256 ethAdjust = ethUsd.decimals < 18 ? SCALE / (10 ** ethUsd.decimals) : 1;
                uint256 ethPrice = ethUsd.price * ethAdjust;
                
                // Convert prices to same denomination
                // If source is in ETH, multiply by ETH/USD price
                // If destination is in ETH, multiply destination by ETH/USD price
                if (params.srcFeed.denomination == PriceDenomination.ETH) {
                    srcPrice = srcPrice.mulDiv(ethPrice, SCALE);
                } else {
                    dstPrice = dstPrice.mulDiv(ethPrice, SCALE);
                }
                
                timestamp = uint64(timestamp < ethUsd.timestamp ? timestamp : ethUsd.timestamp);
            }

            // Step 5: Calculate final price
            // 1. Adjust input amount to 18 decimals
            uint256 amountScaling = srcDecimals < 18 ? SCALE / (10 ** srcDecimals) : 1;
            // 2. Calculate: (amount * srcPrice * scaling) / dstPrice
            price = params.amount.mulDiv(srcPrice * amountScaling, dstPrice);
            
            // Step 6: Scale result to destination decimals
            // If destination has less than 18 decimals, divide by the difference
            if (dstDecimals < 18) {
                price = price / (10 ** (18 - dstDecimals));
            }
        }

        return (price, timestamp);
    }
}
