// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface IAerodromeV1Pool {

    /// @notice Returns [token0, token1]
    function tokens() external view returns (address, address);
    
    /// @notice Address of token in the pool with the lower address value
    function token0() external view returns (address);

    /// @notice Address of token in the poool with the higher address value
    function token1() external view returns (address);

    /// @notice Provides twap price with user configured granularity, up to the full window size
    /// @param tokenIn .
    /// @param amountIn .
    /// @param granularity .
    /// @return amountOut .
    function quote(address tokenIn, uint256 amountIn, uint256 granularity) external view returns (uint256 amountOut);

    /// @notice Returns a memory set of TWAP prices
    ///         Same as calling sample(tokenIn, amountIn, points, 1)
    /// @param tokenIn .
    /// @param amountIn .
    /// @param points Number of points to return
    /// @return Array of TWAP prices
    function prices(address tokenIn, uint256 amountIn, uint256 points) external view returns (uint256[] memory);

    /// @notice Same as prices with with an additional window argument.
    ///         Window = 2 means 2 * 30min (or 1 hr) between observations
    /// @param tokenIn .
    /// @param amountIn .
    /// @param points .
    /// @param window .
    /// @return Array of TWAP prices
    function sample(
        address tokenIn,
        uint256 amountIn,
        uint256 points,
        uint256 window
    ) external view returns (uint256[] memory);

    
    /// @notice Get the amount of tokenOut given the amount of tokenIn
    /// @param amountIn Amount of token in
    /// @param tokenIn  Address of token
    /// @return Amount out
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);
}