// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/// @notice Mock ERC20 optimized implementation
contract MockERC20 {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientBalance();
    error InsufficientAllowance();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(string memory name_, string memory symbol_, uint8 decimals_) {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        if (amount > balanceOf[msg.sender]) revert InsufficientBalance();

        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (amount > allowed) revert InsufficientAllowance();
            allowance[from][msg.sender] = allowed - amount;
        }

        if (amount > balanceOf[from]) revert InsufficientBalance();

        balanceOf[from] -= amount;
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;
        unchecked {
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        if (amount > balanceOf[from]) revert InsufficientBalance();

        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }
        emit Transfer(from, address(0), amount);
    }

    // For testing
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }

    function burn(uint256 amount) public virtual {
        _burn(msg.sender, amount);
    }
}
