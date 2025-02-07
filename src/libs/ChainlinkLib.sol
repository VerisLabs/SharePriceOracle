// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ChainlinkResponse } from "../interfaces/ISharePriceOracle.sol";
import { AggregatorV3Interface } from "../interfaces/AggregatorV3Interface.sol";

import { console2 } from "forge-std/console2.sol";

/// @title ChainlinkLib
/// @notice Library for interacting with Chainlink price feeds
/// @dev Provides safe price retrieval with comprehensive validation
library ChainlinkLib {
    /// @notice Grace period for L2 sequencer validation
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /// @notice Retrieves the latest price data from a Chainlink price feed
    /// @dev Includes full validation of roundId, timestamp, and price value
    /// @param feed Address of the Chainlink price feed
    /// @param heartbeat Heartbeat for the price feed
    /// @return response ChainlinkResponse struct containing price data and metadata
    /// @custom:security Returns zeroed response if any validation fails

    function getPrice(
        address feed,
        address sequencer,
        uint32 heartbeat
    )
        internal
        view
        returns (ChainlinkResponse memory response)
    {
        // Log initial parameters
        console2.log("ChainlinkLib.getPrice called with:");
        console2.log("Feed:", feed);
        console2.log("Sequencer:", sequencer);
        console2.log("Heartbeat:", heartbeat);

        if (sequencer != address(0)) {
            console2.log("Checking sequencer status...");
            try AggregatorV3Interface(sequencer).latestRoundData() returns (
                uint80 seqRoundId, int256 answer, uint256 startedAt, uint256 seqUpdatedAt, uint80 seqAnsweredInRound
            ) {
                console2.log("Sequencer roundId:", seqRoundId);
                console2.log("Sequencer answer:", uint256(answer));
                console2.log("Sequencer startedAt:", startedAt);
                console2.log("Sequencer updatedAt:", seqUpdatedAt);
                console2.log("Sequencer answeredInRound:", seqAnsweredInRound);

                if (answer == 1) {
                    console2.log("Sequencer is down (answer == 1)");
                    return ChainlinkResponse(0, 0, 0, 0, 0);
                }
                if (block.timestamp - startedAt <= GRACE_PERIOD_TIME) {
                    console2.log("Sequencer in grace period");
                    console2.log("Current time:", block.timestamp);
                    console2.log("Time diff:", block.timestamp - startedAt);
                    return ChainlinkResponse(0, 0, 0, 0, 0);
                }
            } catch {
                console2.log("Failed to get sequencer data");
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }
        }

        console2.log("Getting price feed data...");
        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80 roundId, int256 price, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            console2.log("Price feed roundId:", roundId);
            console2.log("Price feed price:", uint256(price));
            console2.log("Price feed updatedAt:", updatedAt);
            console2.log("Price feed answeredInRound:", answeredInRound);

            if (price <= 0) {
                console2.log("Invalid price (<=0)");
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }
            if (roundId == 0) {
                console2.log("Invalid roundId (==0)");
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }
            if (updatedAt == 0) {
                console2.log("Invalid updatedAt (==0)");
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }
            if (answeredInRound < roundId) {
                console2.log("Invalid answeredInRound < roundId");
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            if (block.timestamp - updatedAt > heartbeat) {
                console2.log("Price is stale");
                console2.log("Current time:", block.timestamp);
                console2.log("Time diff:", block.timestamp - updatedAt);
                console2.log("Heartbeat:", heartbeat);
                return ChainlinkResponse(0, 0, 0, 0, 0);
            }

            uint8 decimals;
            try AggregatorV3Interface(feed).decimals() returns (uint8 dec) {
                decimals = dec;
                console2.log("Price feed decimals:", decimals);
            } catch {
                console2.log("Failed to get decimals");
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
            console2.log("Failed to get price feed data");
            return ChainlinkResponse(0, 0, 0, 0, 0);
        }
    }
}
