// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC4626 } from "../../src/interfaces/IERC4626.sol";
import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockERC4626 is IERC4626 {
    uint8 private immutable _decimals;
    uint256 private _sharePrice;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
        _sharePrice = 10 ** decimals_;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function asset() external view returns (address) {
        return address(this);
    }

    function setMockSharePrice(uint256 sharePrice_) external {
        _sharePrice = sharePrice_;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * _sharePrice / (10 ** _decimals);
    }

    // ERC20 storage
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private constant _name = "Mock Vault";
    string private constant _symbol = "mVLT";

    // Conversion functions
    function convertToShares(uint256 assets) external view returns (uint256) {
        return assets * 1e18 / _sharePrice;
    }

    // ERC20 functions
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(to != address(0), "Transfer to zero address");
        address owner = msg.sender;
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // ERC20Metadata functions
    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    // Internal ERC20 functions
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Transfer amount exceeds balance");
        _balances[from] = fromBalance - amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "Approve from zero address");
        require(spender != address(0), "Approve to zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            _approve(owner, spender, currentAllowance - amount);
        }
    }

    // Not implemented ERC4626 functions - these will revert when called
    function totalAssets() external pure returns (uint256) {
        revert("Not implemented");
    }

    function previewDeposit(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }

    function previewMint(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }

    function previewWithdraw(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }

    function previewRedeem(uint256) external pure returns (uint256) {
        revert("Not implemented");
    }

    function maxDeposit(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function maxMint(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function maxWithdraw(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function maxRedeem(address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function deposit(uint256, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function mint(uint256, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function withdraw(uint256, address, address) external pure returns (uint256) {
        revert("Not implemented");
    }

    function redeem(uint256, address, address) external pure returns (uint256) {
        revert("Not implemented");
    }
}
