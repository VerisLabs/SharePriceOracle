// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IBalancerV2Vault
 * @notice Interface for Balancer V2 Vault
 */
interface IBalancerV2Vault {
    /**
     * @notice Returns a Pool's tokens, the total balance for each, and the latest block
     * when any of these balances was updated
     * @param poolId The ID of the Pool
     * @return tokens An array of token addresses
     * @return balances The balances of each token in the pool
     * @return lastChangeBlock The block in which the balances were last modified
     */
    function getPoolTokens(bytes32 poolId)
        external
        view
        returns (address[] memory tokens, uint256[] memory balances, uint256 lastChangeBlock);

    /**
     * @notice Returns the Pool information associated with a Pool ID
     * @param poolId The ID of the Pool
     * @return Pool address and specialization setting
     */
    function getPool(bytes32 poolId) external view returns (address, uint8);
}

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
     * @notice Returns the time of the last swap in the pool
     * @return The timestamp of the last swap
     */
    function getLastSwapTime() external view returns (uint256);
}
