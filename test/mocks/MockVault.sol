// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IERC4626 } from "../../src/interfaces/IERC4626.sol";
import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";

contract MockVault is IERC4626 {
    address public immutable override asset;
    uint8 public immutable override(IERC20, IERC20Metadata) decimals;
    uint256 public sharePrice;
    string public constant override(IERC20, IERC20Metadata) name = "Mock Vault";
    string public constant override(IERC20, IERC20Metadata) symbol = "mVLT";
    uint256 private _totalSupply;

    constructor(address _asset, uint8 _decimals, uint256 _sharePrice) {
        asset = _asset;
        decimals = _decimals;
        sharePrice = _sharePrice;
    }

    function convertToAssets(uint256 shares) external view override returns (uint256) {
        // Calculate based on the asset's actual decimals
        uint256 assetUnit = 10 ** decimals;
        return (shares * sharePrice) / assetUnit;
    }

    // IERC20 implementation
    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address) external pure override returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure override returns (bool) {
        return false;
    }

    function allowance(address, address) external pure override returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure override returns (bool) {
        return false;
    }

    // Required interface stubs
    function totalAssets() external pure override returns (uint256) {
        return 0;
    }

    function convertToShares(uint256) external pure override returns (uint256) {
        return 0;
    }

    function maxDeposit(address) external pure override returns (uint256) {
        return 0;
    }

    function previewDeposit(uint256) external pure override returns (uint256) {
        return 0;
    }

    function deposit(uint256, address) external pure override returns (uint256) {
        return 0;
    }

    function maxMint(address) external pure override returns (uint256) {
        return 0;
    }

    function previewMint(uint256) external pure override returns (uint256) {
        return 0;
    }

    function mint(uint256, address) external pure override returns (uint256) {
        return 0;
    }

    function maxWithdraw(address) external pure override returns (uint256) {
        return 0;
    }

    function previewWithdraw(uint256) external pure override returns (uint256) {
        return 0;
    }

    function withdraw(uint256, address, address) external pure override returns (uint256) {
        return 0;
    }

    function maxRedeem(address) external pure override returns (uint256) {
        return 0;
    }

    function previewRedeem(uint256) external pure override returns (uint256) {
        return 0;
    }

    function redeem(uint256, address, address) external pure override returns (uint256) {
        return 0;
    }
}
