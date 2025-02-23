// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MockERC4626 } from "./MockERC4626.sol";
import { MockERC20 } from "./MockERC20.sol";
import { IERC20 } from "../../src/interfaces/IERC20.sol";

contract MockERC4626Factory {
    function createVault(uint8 decimals_) external returns (MockERC4626) {
        MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", decimals_);
        return new MockERC4626(IERC20(address(mockAsset)), decimals_);
    }

    function createVaultWithAsset(address asset_) external returns (MockERC4626) {
        uint8 decimals_ = MockERC20(asset_).decimals();
        return new MockERC4626(IERC20(asset_), decimals_);
    }
} 