// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ISharePriceOracle } from "../interfaces/ISharePriceOracle.sol";

/**
 * @title MsgCodec
 * @notice Library for encoding and decoding cross-chain messages containing vault data
 * @dev This library handles the serialization and deserialization of messages for LayerZero communication
 *      All functions perform strict validation of message formats and lengths to prevent data corruption
 */
library MsgCodec {
    error MsgCodec__InvalidMessageLength(uint256 provided, uint256 required);
    error MsgCodec__InvalidMessageSlice(uint256 start, uint256 length);
    error MsgCodec__InvalidOptionFormat(bytes options);
    error MsgCodec__ZeroVaultAddress(uint256 index);

    // Proper ABI encoded sizes
    /// @notice Size of a single ISharePriceOracle.VaultReport struct when ABI encoded (7 fields * 32 bytes)
    uint256 private constant VAULT_REPORT_SIZE = 32 * 7;
    /// @notice Size of the message header (msgType + array offset + length + rewardsDelegate)
    uint256 private constant HEADER_SIZE = 32 * 4;
    /// @notice Size of extra options data (option + offset pointer + length)
    uint256 private constant EXTRA_OPTION_SIZE = 3 * 32;
    /// @notice Minimum size for any encoded message
    uint256 private constant MIN_MESSAGE_SIZE = 32;

    /**
     * @notice Encodes vault addresses and options into a cross-chain message
     * @dev Message format: [msgType][addresses_array][rewardsDelegate][options_length][options]
     * @param _msgType Message type identifier (1 for AB, 2 for ABA pattern)
     * @param _message Array of vault addresses to encode
     * @param rewardsDelegate Address to receive rewards
     * @param _extraReturnOptions Additional options for the return message
     * @return Encoded message bytes
     */
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
        return abi.encode(_msgType, _message, rewardsDelegate, _extraReturnOptions.length, _extraReturnOptions);
    }

    /**
     * @notice Encodes vault reports and options into a cross-chain message
     * @dev Performs validation of vault addresses and optimizes gas usage with array length caching
     * @param _msgType Message type identifier (1 for AB, 2 for ABA pattern)
     * @param _reports Array of ISharePriceOracle.VaultReport structs to encode
     * @param _extraReturnOptions Additional options for the return message
     * @return Encoded message bytes
     * @custom:throws MsgCodec__ZeroVaultAddress if any vault address in reports is zero
     */
    function encodeVaultReports(
        uint16 _msgType,
        ISharePriceOracle.VaultReport[] memory _reports,
        bytes memory _extraReturnOptions
    )
        public
        pure
        returns (bytes memory)
    {
        // Cache array length for gas optimization
        uint256 reportsLength = _reports.length;

        // Validate reports
        for (uint256 i; i < reportsLength; ++i) {
            if (_reports[i].vaultAddress == address(0)) {
                revert MsgCodec__ZeroVaultAddress(i);
            }
        }
        return abi.encode(_msgType, _reports, _extraReturnOptions.length, _extraReturnOptions);
    }

    /**
     * @notice Decodes a message containing vault addresses and options
     * @dev Performs extensive validation of message format and length
     * @param encodedMessage The encoded message bytes to decode
     * @return msgType Message type identifier
     * @return message Array of decoded vault addresses
     * @return rewardsDelegate Address to receive rewards
     * @return extraOptionsStart Starting position of extra options in the message
     * @return extraOptionsLength Length of extra options data
     * @custom:throws MsgCodec__InvalidMessageLength if message is too short
     */
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
        if (encodedMessage.length < HEADER_SIZE) {
            revert MsgCodec__InvalidMessageLength(encodedMessage.length, HEADER_SIZE);
        }

        (msgType, message, rewardsDelegate, extraOptionsLength) =
            abi.decode(encodedMessage, (uint16, address[], address, uint256));

        // Cache array length for gas optimization
        uint256 messageLength = message.length;
        extraOptionsStart = HEADER_SIZE + EXTRA_OPTION_SIZE + (messageLength * 32);

        // Validate that the message contains at least the base data (excluding options)
        if (encodedMessage.length < extraOptionsStart) {
            revert MsgCodec__InvalidMessageLength(encodedMessage.length, extraOptionsStart);
        }

        return (msgType, message, rewardsDelegate, extraOptionsStart, extraOptionsLength);
    }

    /**
     * @notice Decodes a message containing vault reports and options
     * @dev Performs extensive validation of message format and length
     * @param encodedMessage The encoded message bytes to decode
     * @return msgType Message type identifier
     * @return reports Array of decoded ISharePriceOracle.VaultReport structs
     * @return extraOptionsStart Starting position of extra options in the message
     * @return extraOptionsLength Length of extra options data
     * @custom:throws MsgCodec__InvalidMessageLength if message is too short
     */
    function decodeVaultReports(bytes calldata encodedMessage)
        public
        pure
        returns (
            uint16 msgType,
            ISharePriceOracle.VaultReport[] memory reports,
            uint256 extraOptionsStart,
            uint256 extraOptionsLength
        )
    {
        if (encodedMessage.length < HEADER_SIZE) {
            revert MsgCodec__InvalidMessageLength(encodedMessage.length, HEADER_SIZE);
        }

        (msgType, reports, extraOptionsLength) =
            abi.decode(encodedMessage, (uint16, ISharePriceOracle.VaultReport[], uint256));

        // Cache array length for gas optimization
        uint256 reportsLength = reports.length;
        extraOptionsStart = HEADER_SIZE + EXTRA_OPTION_SIZE + (reportsLength * VAULT_REPORT_SIZE);

        // Validate that the message contains at least the base data (excluding options)
        if (encodedMessage.length < extraOptionsStart) {
            revert MsgCodec__InvalidMessageLength(encodedMessage.length, extraOptionsStart);
        }

        return (msgType, reports, extraOptionsStart, extraOptionsLength);
    }

    /**
     * @notice Extracts the message type from an encoded message
     * @dev Uses assembly for efficient access to the first 2 bytes of the message
     * @param encodedMessage The encoded message bytes
     * @return msgType The 16-bit message type identifier
     * @custom:throws MsgCodec__InvalidMessageLength if message is shorter than MIN_MESSAGE_SIZE
     */
    function decodeMsgType(bytes calldata encodedMessage) public pure returns (uint16 msgType) {
        if (encodedMessage.length < MIN_MESSAGE_SIZE) {
            revert MsgCodec__InvalidMessageLength(encodedMessage.length, MIN_MESSAGE_SIZE);
        }

        assembly {
            let word := calldataload(encodedMessage.offset)
            msgType := and(word, 0xffff)
        }
    }
}
