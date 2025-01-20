// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

/// @title PriceConversionLib
/// @notice Library for converting prices between different assets using Chainlink price feeds
/// @dev Uses FixedPointMathLib for safe mathematical operations
library PriceConversionLib {
    using FixedPointMathLib for uint256;

    struct PriceConversion {
        uint256 amount;
        uint256 srcPrice;
        uint256 dstPrice;
        uint8 srcDecimals;
        uint8 dstDecimals;
        uint256 srcTimestamp;
        uint256 dstTimestamp;
    }

    /// @notice Converts an amount from one asset to another using their respective prices
    /// @dev Uses full precision multiplication and division to prevent overflow and maintain precision
    /// @param conv PriceConversion struct containing conversion parameters
    /// @return price The converted price in terms of the destination asset
    /// @return timestamp The earlier timestamp between source and destination prices
    function convertAssetPrice(
        PriceConversion memory conv
    ) internal pure returns (uint256 price, uint64 timestamp) {
        if (conv.srcPrice == 0 || conv.dstPrice == 0) return (0, 0);
          
        uint256 normalizedAmount = conv.amount;

        // Convert to USD using source price
        uint256 amountInUsd = normalizedAmount.mulDiv(conv.srcPrice, 10 ** conv.srcDecimals);

        // Convert USD amount to destination asset
        price = amountInUsd.mulDiv(10 ** conv.dstDecimals, conv.dstPrice);
        
        timestamp = uint64(
            conv.srcTimestamp < conv.dstTimestamp
                ? conv.srcTimestamp
                : conv.dstTimestamp
        );
    }
}
