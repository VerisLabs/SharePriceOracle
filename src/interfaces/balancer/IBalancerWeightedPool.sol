// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IBalancerWeightedPool {
    function getPoolId() external view returns (bytes32);
    function getNormalizedWeights() external view returns (uint256[] memory);
    function getLastInvariant() external view returns (uint256);
    function getLastInvariantCalculationTimestamp() external view returns (uint256);
} 