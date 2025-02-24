// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { VaultReport } from "../interfaces/ISharePriceRouter.sol";

library MsgCodec {
    error MsgCodec__InvalidMessageLength();
    error MsgCodec__InvalidMessageSlice();
    error MsgCodec__InvalidOptionFormat();
    error MsgCodec__ZeroVaultAddress();

    // Proper ABI encoded sizes
    uint256 private constant VAULT_REPORT_SIZE = 32 * 7; // Each field padded to 32 bytes in ABI encoding
    uint256 private constant HEADER_SIZE = 32 * 4; // msgType + array offset + length + rewardsDelegate
    uint256 private constant EXTRA_OPTION_SIZE = 3 * 32; // option + offset pointer + length
    uint256 private constant MIN_MESSAGE_SIZE = 32; // Minimum size for any encoded message

    function encodeVaultAddresses(
        uint16 _msgType,
        address[] memory _message,
        address rewardsDelegate,
        bytes memory _extraReturnOptions
    )
        public
        pure
        returns (bytes memory)
    {
        // Format: [msgType][addresses_array][options_length][options]
        return abi.encode(_msgType, _message, rewardsDelegate, _extraReturnOptions.length, _extraReturnOptions);
    }

    function encodeVaultReports(
        uint16 _msgType,
        VaultReport[] memory _reports,
        bytes memory _extraReturnOptions
    )
        public
        pure
        returns (bytes memory)
    {
        // Validate reports
        for (uint256 i = 0; i < _reports.length; i++) {
            if (_reports[i].vaultAddress == address(0)) revert MsgCodec__ZeroVaultAddress();
        }
        return abi.encode(_msgType, _reports, _extraReturnOptions.length, _extraReturnOptions);
    }

    function decodeVaultAddresses(bytes calldata encodedMessage)
        public
        pure
        returns (
            uint16 msgType,
            address[] memory message,
            address rewardsDelegate,
            uint256 extraOptionsStart,
            uint256 extraOptionsLength
        )
    {
        if (encodedMessage.length < HEADER_SIZE) revert MsgCodec__InvalidMessageLength();

        (msgType, message, rewardsDelegate, extraOptionsLength) =
            abi.decode(encodedMessage, (uint16, address[], address, uint256));

        extraOptionsStart = HEADER_SIZE + EXTRA_OPTION_SIZE + (message.length * 32);

        return (msgType, message, rewardsDelegate, extraOptionsStart, extraOptionsLength);
    }

    function decodeVaultReports(bytes calldata encodedMessage)
        public
        pure
        returns (uint16 msgType, VaultReport[] memory reports, uint256 extraOptionsStart, uint256 extraOptionsLength)
    {
        if (encodedMessage.length < HEADER_SIZE) revert MsgCodec__InvalidMessageLength();

        (msgType, reports, extraOptionsLength) = abi.decode(encodedMessage, (uint16, VaultReport[], uint256));

        extraOptionsStart = HEADER_SIZE + EXTRA_OPTION_SIZE + (reports.length * VAULT_REPORT_SIZE);

        return (msgType, reports, extraOptionsStart, extraOptionsLength);
    }

    function decodeMsgType(bytes calldata encodedMessage) public pure returns (uint16 msgType) {
        if (encodedMessage.length < MIN_MESSAGE_SIZE) revert MsgCodec__InvalidMessageLength();

        assembly {
            let word := calldataload(encodedMessage.offset)
            msgType := and(word, 0xffff)
        }
    }
}
