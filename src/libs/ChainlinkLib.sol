// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ChainlinkResponse} from "../interfaces/ISharePriceOracle.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

library ChainlinkLib {
    function getPrice(
        address feed
    ) internal view returns (ChainlinkResponse memory response) {
        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (
                price <= 0 ||
                roundId == 0 ||
                updatedAt == 0 ||
                answeredInRound < roundId
            ) {
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            uint8 decimals;
            try AggregatorV3Interface(feed).decimals() returns (uint8 dec) {
                decimals = dec;
            } catch {
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            return ChainlinkResponse({
                price: uint256(price),
                decimals: decimals,
                timestamp: updatedAt,
                roundId: roundId,
                answeredInRound: answeredInRound
            });
        } catch {
            return ChainlinkResponse(0, 0, 0, 0, 0);
        }
    }
}
