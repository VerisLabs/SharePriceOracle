// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IProxy {
    /// @notice Reads the dAPI that this proxy maps to
    /// @return value dAPI value
    /// @return timestamp dAPI timestamp
    function read() external view returns (int224 value, uint32 timestamp);
    /// @notice Api3ServerV1 address
    function api3ServerV1() external view returns (address);
    /// @notice Name of the dAPI
    function dapiName() external view returns (bytes32);
}
