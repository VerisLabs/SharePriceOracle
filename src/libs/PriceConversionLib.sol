// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";

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

    function convertAssetPrice(
        PriceConversion memory conv
    ) internal pure returns (uint256 price, uint64 timestamp) {
        if (conv.srcPrice == 0 || conv.dstPrice == 0) return (0, 0);

        price = conv.amount.fullMulDiv(conv.srcPrice, conv.dstPrice).mulDiv(
            10 ** conv.dstDecimals,
            10 ** conv.srcDecimals
        );

        timestamp = uint64(
            conv.srcTimestamp < conv.dstTimestamp 
                ? conv.srcTimestamp 
                : conv.dstTimestamp
        );
    }
}
