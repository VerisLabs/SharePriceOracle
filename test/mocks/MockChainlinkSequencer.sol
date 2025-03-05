// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract MockChainlinkSequencer {
    bool public isDown = false;
    uint256 public startedAt;

    constructor() {
        startedAt = block.timestamp - 1 days; // Default to started long ago
    }

    function setDown() external {
        isDown = true;
    }

    function setUp() external {
        isDown = false;
    }

    function setStartedAt(uint256 _startedAt) external {
        startedAt = _startedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt_, uint256 updatedAt, uint80 answeredInRound)
    {
        return (
            uint80(1), // roundId
            isDown ? int256(1) : int256(0), // answer (0 = up, 1 = down)
            startedAt, // startedAt
            block.timestamp, // updatedAt
            uint80(1) // answeredInRound
        );
    }
}
