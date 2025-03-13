// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IBalancerV2WeightedPool
 * @notice Interface for Balancer V2 Weighted Pool
 */
interface IBalancerV2WeightedPool {
    /**
     * @notice Returns the current value of the normalization weights for each token
     * @return The normalization weight of each token in the pool
     */
    function getNormalizedWeights() external view returns (uint256[] memory);

    /**
     * @notice Returns the pool's last change block
     * @return The block number of the last change to the pool
     */
    function getLastChangeBlock() external view returns (uint256);
}
