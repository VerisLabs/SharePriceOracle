// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { getTokensList } from "../helpers/Tokens.sol";
import { IERC20 } from "../interfaces/IERC20.sol";
import { Utilities } from "../utils/Utilities.sol";
import { Test, Vm } from "forge-std/Test.sol";

contract BaseTest is Test {
    struct Users {
        address payable alice;
        address payable bob;
        address payable eve;
        address payable charlie;
        address payable keeper;
        address payable allocator;
    }

    Utilities public utils;
    Users public users;
    mapping(string => uint256) public chainForks;

    uint256 internal constant MAX_BPS = 10_000;

    function _createFork(string memory chain, uint256 forkBlock) internal returns (uint256) {
        string memory rpc = vm.envString(string.concat(chain, "_RPC_URL"));
        uint256 fork = vm.createSelectFork(rpc);
        vm.rollFork(forkBlock);

        return fork;
    }

    function _setUp(string[] memory chains, uint256[] memory forkBlocks) internal virtual {
        require(chains.length == forkBlocks.length, "chains and blocks length mismatch");

        // Create forks for each chain
        for (uint256 i = 0; i < chains.length; i++) {
            chainForks[chains[i]] = _createFork(chains[i], forkBlocks[i]);
        }

        // Setup utils
        utils = new Utilities();
    }

    // Helper function to switch between forks
    function switchTo(string memory chain) internal virtual {
        vm.selectFork(chainForks[chain]);
    }

    function assertRelApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxPercentDelta // An 18 decimal fixed point number, where 1e18 == 100%
    )
        internal
        virtual
    {
        if (b == 0) return assertEq(a, b); // If the expected is 0, actual must be too.

        uint256 percentDelta = ((a > b ? a - b : b - a) * 1e18) / b;

        if (percentDelta > maxPercentDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("    Expected", b);
            emit log_named_uint("      Actual", a);
            emit log_named_decimal_uint(" Max % Delta", maxPercentDelta, 18);
            emit log_named_decimal_uint("     % Delta", percentDelta, 18);
            fail();
        }
    }

    function assertApproxEq(uint256 a, uint256 b, uint256 maxDelta) internal virtual {
        uint256 delta = a > b ? a - b : b - a;

        if (delta > maxDelta) {
            emit log("Error: a ~= b not satisfied [uint]");
            emit log_named_uint("  Expected", b);
            emit log_named_uint("    Actual", a);
            emit log_named_uint(" Max Delta", maxDelta);
            emit log_named_uint("     Delta", delta);
            fail();
        }
    }
}
