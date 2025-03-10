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
    
 
    function getPool(bytes32 poolId) external view returns (address pool, uint8 specialization);
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
     * @notice Returns the pool's last change block
     * @return The block number of the last change to the pool
     */
    function getLastChangeBlock() external view returns (uint256);
}