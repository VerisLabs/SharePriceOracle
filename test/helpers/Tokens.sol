// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { USDCE_BASE, USDCE_POLYGON, USDC_MAINNET, WETH_MAINNET } from "../utils/AddressBook.sol";

uint256 constant _1_USDC = 1e6;
uint256 constant _1_USDCE = 1e6;

function getTokensList(string memory chain) pure returns (address[] memory) {
    if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("MAINNET"))) {
        address[] memory tokens = new address[](2);
        tokens[0] = WETH_MAINNET;
        tokens[1] = USDC_MAINNET;
        return tokens;
    } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("POLYGON"))) {
        address[] memory tokens = new address[](1);
        tokens[0] = USDCE_POLYGON;
        return tokens;
    } else if (keccak256(abi.encodePacked(chain)) == keccak256(abi.encodePacked("BASE"))) {
        address[] memory tokens = new address[](1);
        tokens[0] = USDCE_BASE;
        return tokens;
    } else {
        revert("InvalidChain");
    }
}
