// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ChainlinkResponse } from "../interfaces/ISharePriceOracle.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

/// @title ChainlinkLib
/// @notice Library for interacting with Chainlink price feeds
/// @dev Provides safe price retrieval with comprehensive validation
library ChainlinkLib {
    /// @notice Retrieves the latest price data from a Chainlink price feed
    /// @dev Includes full validation of roundId, timestamp, and price value
    /// @param feed Address of the Chainlink price feed
    /// @param heartbeat Heartbeat for the price feed
    /// @return response ChainlinkResponse struct containing price data and metadata
    /// @custom:security Returns zeroed response if any validation fails
    function getPrice(address feed, uint32 heartbeat) internal view returns (ChainlinkResponse memory response) {
        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80 roundId, int256 price, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (price <= 0 || roundId == 0 || updatedAt == 0 || answeredInRound < roundId) {
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            // Check for stale price based on provided heartbeat
            if (block.timestamp - updatedAt > heartbeat) {
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            // Get decimals
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
