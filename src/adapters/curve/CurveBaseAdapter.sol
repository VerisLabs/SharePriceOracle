// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../../libs/base/BaseOracleAdapter.sol";

import { ICurveRemoveLiquidity } from "src/interfaces/curve/ICurveRemoveLiquidity.sol";

/// @dev Kudos to Curve Finance/Silo Finance/Chain Security for researching
///      specific gas limit values for Pool Reentrancy.
abstract contract CurveBaseAdapter is BaseOracleAdapter {
    /// CONSTANTS ///

    /// @notice Minimum gas limit allowed for reentrancy check configuration.
    uint256 public constant MIN_GAS_LIMIT = 6000;

    /// STORAGE ///

    /// @notice Configuration data for verifying whether a pool is inside
    ///         a reentry context or not.
    /// @dev The number of underlying tokens inside a pool => Maximum
    ///      gas allowed in Reentry check.
    mapping(uint256 => uint256) public reentrancyConfig;

    /// EVENTS ///

    event UpdatedReentrancyConfiguration(
        uint256 coinsLength,
        uint256 gasLimit
    );

    /// ERRORS ///

    error CurveBaseAdapter__PoolNotFound();
    error CurveBaseAdapter__InvalidConfiguration();

    /// CONSTRUCTOR ///

    /// CONSTRUCTOR ///

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter
    ) BaseOracleAdapter (_admin, _oracle, _oracleRouter) {}


    /// PUBLIC FUNCTIONS ///

    /// @notice Verifies if the reentry lock is active on the Curve pool,
    ///         this is done by calling remove_liquidity and making sure
    ///         that there was not excess gas remaining on the call, as that
    ///         means they currently are in the remove liquidity context and
    ///         are manipulating the virtual price.
    /// @param curvePool The address of the Curve pool to check for Reentry.
    /// @param coinsLength The number of underlying tokens inside `pool`. 
    function isLocked(
        address curvePool,
        uint256 coinsLength
    ) public view returns (bool) {
        uint256 gasLimit = reentrancyConfig[coinsLength];

        if (gasLimit == 0) {
            revert CurveBaseAdapter__PoolNotFound();
        }

        uint256 gasStart = gasleft();

        ICurveRemoveLiquidity pool = ICurveRemoveLiquidity(curvePool);

        if (coinsLength == 2) {
            uint256[2] memory amounts;
            try pool.remove_liquidity{ gas: gasLimit }(0, amounts) {} catch (
                bytes memory
            ) {}
        } else if (coinsLength == 3) {
            uint256[3] memory amounts;
            try pool.remove_liquidity{ gas: gasLimit }(0, amounts) {} catch (
                bytes memory
            ) {}
        }
        if (coinsLength == 4) {
            uint256[4] memory amounts;
            try pool.remove_liquidity{ gas: gasLimit }(0, amounts) {} catch (
                bytes memory
            ) {}
        }

        uint256 gasSpent;
        // `gasStart` will be always > `gasleft()`
        unchecked {
            gasSpent = gasStart - gasleft();
        }

        return
            gasSpent > gasLimit
                ? false /* is not locked */
                : true /* locked */;
    }

    /// INTERNAL FUNCTIONS ///

    /// @notice Sets or updates a Curve pool configuration for the reentrancy check.
    /// @param coinsLength The number of coins (from .coinsLength) on the Curve pool.
    /// @param gasLimit The gas limit to be set on the check.
    function _setReentrancyConfig(
        uint256 coinsLength,
        uint256 gasLimit
    ) internal {
        // Make sure the gas limit assigned is above the minimum for the pool
        if (gasLimit < MIN_GAS_LIMIT) {
            revert CurveBaseAdapter__InvalidConfiguration();
        }

        // Make sure the pool is not above 4 or below 2underlying tokens,
        // we limit pools to 4.
        if (coinsLength < 2 || coinsLength > 4) {
            revert CurveBaseAdapter__InvalidConfiguration();
        }

        reentrancyConfig[coinsLength] = gasLimit;
        emit UpdatedReentrancyConfiguration(coinsLength, gasLimit);
    }
}