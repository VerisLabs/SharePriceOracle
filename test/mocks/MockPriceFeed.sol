// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint8 private constant _decimals = 18; // Changed to 18 decimals for ETH feeds
    uint80 private _roundId = 1;
    int256 private _price;
    uint256 private _timestamp;
    uint80 private _answeredInRound;

    constructor() {
        _timestamp = block.timestamp;
        _answeredInRound = _roundId;
    }

    function setPrice(int256 price) external {
        _price = price;
        _roundId++;
        _timestamp = block.timestamp;
        _answeredInRound = _roundId;
    }

    function decimals() external pure returns (uint8) {
        return _decimals;
    }

    function description() external pure returns (string memory) {
        return "Mock Price Feed";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _timestamp, _timestamp, _answeredInRound);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, _timestamp, _timestamp, _answeredInRound);
    }

    function latestAnswer() external view returns (int256) {
        return _price;
    }
}
