// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "../../src/interfaces/IERC20.sol";
import { IERC20Metadata } from "../../src/interfaces/IERC20Metadata.sol";

contract MockERC20 is IERC20, IERC20Metadata {
    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
    }

    function name() external pure override(IERC20, IERC20Metadata) returns (string memory) {
        return "Mock Token";
    }

    function symbol() external pure override(IERC20, IERC20Metadata) returns (string memory) {
        return "MOCK";
    }

    function decimals() external pure override(IERC20, IERC20Metadata) returns (uint8) {
        return 18;
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

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");

        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        _approve(owner, spender, currentAllowance - amount);
    }

    function mint(address to, uint256 amount) external {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(_balances[from] >= amount, "ERC20: burn amount exceeds balance");
        _balances[from] -= amount;
        _totalSupply -= amount;
        emit Transfer(from, address(0), amount);
    }
}
