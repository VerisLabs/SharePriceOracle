// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.17;

interface ICurvePool {
    function balances(uint256 i) external view returns (uint256);

    function coins(uint256 i) external view returns (address);

    function get_virtual_price() external view returns (uint256);

    function claim_admin_fees() external; // For USDT/WETH/WBTC

    function withdraw_admin_fees() external;

    function gamma() external view returns (uint256);

    function A() external view returns (uint256);

    function lp_price() external view returns (uint256);

    function price_oracle() external view returns (uint256);

    function price_oracle(uint256 i) external view returns (uint256);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external payable returns (uint256);

    function stored_rates() external view returns (uint256[2] memory);

    function get_dy(uint256 from, uint256 to, uint256 _from_amount) external view returns (uint256);
}
