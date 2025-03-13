// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IRedstoneAdapter
 * @notice Interface for the Redstone adapter contract
 */
interface IRedstoneAdapter {
    /**
     * @notice Returns data timestamp from the latest update
     * @return lastDataTimestamp Timestamp of the latest reported data packages (in milliseconds)
     */
    function getDataTimestampFromLatestUpdate() external view returns (uint256 lastDataTimestamp);
    
    /**
     * @notice Returns the latest properly reported value of the data feed
     * @param dataFeedId The identifier of the requested data feed
     * @return value The latest value of the given data feed
     */
    function getValueForDataFeed(bytes32 dataFeedId) external view returns (uint256);
}