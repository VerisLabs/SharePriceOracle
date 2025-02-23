// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MockApi3Proxy {
    bytes32 public dapiName;
    int224 public value;
    uint32 public timestamp;

    constructor(
        string memory _name,
        int224 _value,
        uint256 _timestamp
    ) {
        dapiName = bytes32(bytes(_name));
        value = _value;
        timestamp = uint32(_timestamp);
    }

    function read() external view returns (int224, uint32) {
        return (value, timestamp);
    }

    function setValue(int224 _value) external {
        value = _value;
    }

    function setTimestamp(uint32 _timestamp) external {
        timestamp = _timestamp;
    }
} 