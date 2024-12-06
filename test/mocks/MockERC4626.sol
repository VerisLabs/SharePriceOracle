// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MockERC20 } from "./MockERC20.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

/// @notice Mock ERC4626 implementation
contract MockERC4626 is MockERC20 {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    MockERC20 public immutable asset;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    // For testing: allow manual setting of share price
    uint256 public sharePrice;
    bool public mockPriceEnabled;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address asset_,
        string memory name_,
        string memory symbol_
    )
        MockERC20(name_, symbol_, MockERC20(asset_).decimals())
    {
        asset = MockERC20(asset_);
        sharePrice = 10 ** decimals;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 assets, address receiver) public virtual returns (uint256 shares) {
        shares = previewDeposit(assets);

        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares);

        asset.transferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function withdraw(uint256 assets, address receiver, address owner) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        _burn(owner, shares);
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) public virtual returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        assets = previewRedeem(shares);
        _burn(owner, shares);
        asset.transfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return assets;

        if (mockPriceEnabled) {
            return assets.mulDiv(10 ** decimals, sharePrice);
        }

        return assets.mulDiv(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return sharePrice;

        if (mockPriceEnabled) {
            return shares.mulDiv(sharePrice, 10 ** decimals);
        }

        return shares.mulDiv(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return shares;

        if (mockPriceEnabled) {
            return shares.mulDivUp(sharePrice, 10 ** decimals);
        }

        return shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply;
        if (supply == 0) return 0;

        if (mockPriceEnabled) {
            return assets.mulDivUp(10 ** decimals, sharePrice);
        }

        return assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        return convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public pure virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxMint(address) public pure virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                          TESTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setMockSharePrice(uint256 newPrice) external {
        sharePrice = newPrice;
        mockPriceEnabled = true;
    }

    function disableMockPrice() external {
        mockPriceEnabled = false;
    }
}
