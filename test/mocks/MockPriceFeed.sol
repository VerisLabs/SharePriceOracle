// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "../../src/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 private _decimals;
    uint80 private _roundId;
    int256 private _price;
    uint256 private _timestamp;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    bool private _isSequencer;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _roundId = 1;
        _timestamp = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = 1;
        _price = 1e8; 
    }

    function setPrice(int256 price) external {
        _price = price;
        _roundId = _roundId + 1;
        _timestamp = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = _roundId;
    }

    function setTimestamp(uint256 timestamp_) external {
        _timestamp = timestamp_;
        _updatedAt = timestamp_;
    }

    function setSequencerStatus(bool isDown) external {
        _isSequencer = true;
        if (isDown) {
            _price = 1; // 1 means sequencer is down
        } else {
            _price = 0; // 0 means sequencer is up
        }
        _roundId = _roundId + 1;
        _timestamp = block.timestamp;
        _updatedAt = block.timestamp;
        _answeredInRound = _roundId;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _timestamp, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _timestamp, _updatedAt, _answeredInRound);
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }
}
