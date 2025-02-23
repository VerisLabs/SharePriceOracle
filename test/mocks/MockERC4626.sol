// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";
import { IERC4626 } from "../../src/interfaces/IERC4626.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockERC4626Factory {
    function createVault(uint8 decimals_) external returns (MockERC4626) {
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", decimals_);
        return new MockERC4626(mockAsset, decimals_);
    }

    function createVaultWithAsset(address asset_) external returns (MockERC4626) {
        uint8 decimals_ = IERC20Metadata(asset_).decimals();
        return new MockERC4626(IERC20(asset_), decimals_);
    }
}

contract MockERC4626 is IERC20, IERC20Metadata, IERC4626 {
    IERC20 private immutable _asset;
    uint8 private immutable _decimals;
    uint256 private _mockSharePrice;
    
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    constructor(IERC20 asset_, uint8 decimals_) {
        _asset = asset_;
        _decimals = decimals_;
        _mockSharePrice = 1e18; // Default 1:1 ratio
    }

    function setMockSharePrice(uint256 newSharePrice) external {
        _mockSharePrice = newSharePrice;
    }

    function decimals() external view override(IERC20, IERC20Metadata) returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override(IERC20) returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override(IERC20) returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override(IERC20) returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view override(IERC20) returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external override(IERC20) returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override(IERC20) returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function asset() external view override(IERC4626) returns (address) {
        return address(_asset);
    }

    function convertToShares(uint256 assets) external view override(IERC4626) returns (uint256) {
        return assets * 1e18 / _mockSharePrice;
    }

    function convertToAssets(uint256 shares) external view override(IERC4626) returns (uint256) {
        return shares * _mockSharePrice / 1e18;
    }

    function maxDeposit(address) external pure override(IERC4626) returns (uint256) {
        return type(uint256).max;
    }

    function previewDeposit(uint256 assets) external pure override(IERC4626) returns (uint256) {
        return assets;
    }

    function deposit(uint256 assets, address receiver) external override(IERC4626) returns (uint256) {
        _deposit(msg.sender, receiver, assets);
        return assets;
    }

    function maxMint(address) external pure override(IERC4626) returns (uint256) {
        return type(uint256).max;
    }

    function previewMint(uint256 shares) external pure override(IERC4626) returns (uint256) {
        return shares;
    }

    function mint(uint256 shares, address receiver) external override(IERC4626) returns (uint256) {
        _deposit(msg.sender, receiver, shares);
        return shares;
    }

    function maxWithdraw(address owner) external view override(IERC4626) returns (uint256) {
        return _balances[owner];
    }

    function previewWithdraw(uint256 assets) external pure override(IERC4626) returns (uint256) {
        return assets;
    }

    function withdraw(uint256 assets, address receiver, address owner) external override(IERC4626) returns (uint256) {
        _withdraw(msg.sender, receiver, owner, assets);
        return assets;
    }

    function maxRedeem(address owner) external view override(IERC4626) returns (uint256) {
        return _balances[owner];
    }

    function previewRedeem(uint256 shares) external pure override(IERC4626) returns (uint256) {
        return shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external override(IERC4626) returns (uint256) {
        _withdraw(msg.sender, receiver, owner, shares);
        return shares;
    }

    function name() external pure override(IERC20, IERC20Metadata) returns (string memory) {
        return "Mock Vault";
    }

    function symbol() external pure override(IERC20, IERC20Metadata) returns (string memory) {
        return "mVLT";
    }

    function totalAssets() external view override(IERC4626) returns (uint256) {
        return _asset.balanceOf(address(this));
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC4626: transfer from the zero address");
        require(to != address(0), "ERC4626: transfer to the zero address");
        require(_balances[from] >= amount, "ERC4626: transfer amount exceeds balance");

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC4626: approve from the zero address");
        require(spender != address(0), "ERC4626: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= amount, "ERC4626: insufficient allowance");
        _approve(owner, spender, currentAllowance - amount);
    }

    function _deposit(address caller, address receiver, uint256 amount) internal {
        require(caller != address(0), "ERC4626: deposit from the zero address");
        require(receiver != address(0), "ERC4626: deposit to the zero address");

        _asset.transferFrom(caller, address(this), amount);
        _mint(receiver, amount);

        emit Deposit(caller, receiver, amount, amount);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 amount) internal {
        require(caller != address(0), "ERC4626: withdraw from the zero address");
        require(receiver != address(0), "ERC4626: withdraw to the zero address");
        require(owner != address(0), "ERC4626: withdraw from the zero address");

        if (caller != owner) {
            uint256 currentAllowance = _allowances[owner][caller];
            require(currentAllowance >= amount, "ERC4626: insufficient allowance");
            _approve(owner, caller, currentAllowance - amount);
        }

        _burn(owner, amount);
        _asset.transfer(receiver, amount);

        emit Withdraw(caller, receiver, owner, amount, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC4626: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC4626: burn from the zero address");
        require(_balances[account] >= amount, "ERC4626: burn amount exceeds balance");
        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}
