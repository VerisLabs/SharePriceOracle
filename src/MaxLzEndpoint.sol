// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { ILayerZeroReceiver } from "./interfaces/ILayerZeroReceiver.sol";
import {
    ILayerZeroEndpointV2,
    MessagingParams,
    MessagingFee,
    MessagingReceipt,
    Origin
} from "./interfaces/ILayerZeroEndpointV2.sol";
import { ISharePriceOracle, VaultReport } from "./interfaces/ISharePriceOracle.sol";
import { Ownable } from "@solady/auth/Ownable.sol";
import { MsgCodec } from "./libs/MsgCodec.sol";

contract MaxLzEndpoint is ILayerZeroReceiver, Ownable {
    /// @notice Protocol version identifiers for LayerZero communication
    uint64 private constant SENDER_VERSION = 1;
    uint64 private constant RECEIVER_VERSION = 2;

    /// @notice Option types and limits for message configuration
    uint16 private constant TYPE_3 = 3; // Advanced messaging pattern support
    uint8 private constant WORKER_ID = 1; // Standard executor identifier

    /// @notice Message pattern identifiers
    uint8 private constant AB_TYPE = 1; // Simple send-receive
    uint8 private constant ABA_TYPE = 2; // Request-response pattern

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Contract immutable state
    ISharePriceOracle public immutable oracle;

    /// @notice Contract storage state
    ILayerZeroEndpointV2 public endpoint;
    mapping(bytes32 => bool) public processedMessages;
    mapping(uint32 => mapping(uint16 => bytes)) public enforcedOptions;
    mapping(uint32 eid => bytes32 peer) public peers;

    ////////////////////////////////////////////////////////////////
    ///                          EVENTS                           ///
    ////////////////////////////////////////////////////////////////

    event MessageProcessed(bytes32 indexed guid, bytes message);
    event PeerSet(uint32 indexed eid, bytes32 peer);
    event EndpointUpdated(address indexed oldEndpoint, address indexed newEndpoint);
    event SharePricesSent(uint32 indexed dstEid, address[] vaults);
    event SharePricesRequested(uint32 indexed dstEid, address[] vaults);
    event EnforcedOptionsSet(EnforcedOptionParam[] params);
    event VaultReportsSent(uint32 indexed dstEid, VaultReport[] reports);
    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);

    ////////////////////////////////////////////////////////////////
    ///                          ERRORS                           ///
    ////////////////////////////////////////////////////////////////

    error MessageAlreadyProcessed();
    error InvalidMessageValue();
    error InvalidOptionType(uint16 optionType);
    error InvalidOptions(bytes options);
    error OnlyEndpoint();
    error PeerNotSet(uint32 eid);
    error EndpointExists();
    error InvalidInput();
    error InsufficientFunds();
    error ZeroAddress();
    error InvalidFee();
    error InvalidRole();

    ////////////////////////////////////////////////////////////////
    ///                         STRUCTS                           ///
    ////////////////////////////////////////////////////////////////

    struct EnforcedOptionParam {
        uint32 eid; // Endpoint ID
        uint16 msgType; // Message type
        bytes options; // LayerZero options
    }

    ////////////////////////////////////////////////////////////////
    ///                      CONSTRUCTOR                          ///
    ////////////////////////////////////////////////////////////////

    constructor(address admin_, address lzEndpoint, address oracle_) {
        if (admin_ == address(0) || oracle_ == address(0)) revert ZeroAddress();

        oracle = ISharePriceOracle(oracle_);
        endpoint = ILayerZeroEndpointV2(lzEndpoint);

        _initializeOwner(admin_);
    }

    ////////////////////////////////////////////////////////////////
    ///                    ADMIN FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////

    function setLzEndpoint(address endpoint_) external onlyOwner {
        if (address(endpoint) != address(0)) revert EndpointExists();
        if (endpoint_ == address(0)) revert InvalidInput();
        endpoint = ILayerZeroEndpointV2(endpoint_);
        emit EndpointUpdated(address(0), endpoint_);
    }

    function setPeer(uint32 eid_, bytes32 peer_) external onlyOwner {
        if (peer_ == bytes32(0)) revert InvalidInput();
        peers[eid_] = peer_;
        emit PeerSet(eid_, peer_);
    }

    function setEnforcedOptions(EnforcedOptionParam[] calldata params) external onlyOwner {
        uint256 len = params.length;
        for (uint256 i = 0; i < len;) {
            _assertOptionsType3(params[i].options);
            enforcedOptions[params[i].eid][params[i].msgType] = params[i].options;
            unchecked {
                ++i;
            }
        }
        emit EnforcedOptionsSet(params);
    }

    /// @notice Allows owner to withdraw stuck ETH from the contract
    /// @param amount Amount of ETH to withdraw
    /// @param refundTo Address to receive the withdrawn ETH
    function refundETH(uint256 amount, address refundTo) external onlyOwner {
        if (refundTo == address(0)) revert ZeroAddress();
        if (amount == 0 || amount > address(this).balance) revert InvalidInput();

        (bool success,) = refundTo.call{ value: amount }("");
        if (!success) revert InsufficientFunds();
    }

    ////////////////////////////////////////////////////////////////
    ///                   EXTERNAL FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    function sendSharePrices(
        uint32 dstEid,
        address[] calldata vaultAddresses,
        bytes calldata options,
        address rewardsDelegate
    )
        external
        payable
    {
        VaultReport[] memory reports = oracle.getSharePrices(vaultAddresses, rewardsDelegate);
        bytes memory message = MsgCodec.encodeVaultReports(AB_TYPE, reports, options);
        bytes memory combinedOptions = _getCombinedOptions(dstEid, AB_TYPE, options);

        MessagingFee memory fee = _quote(dstEid, message, combinedOptions);
        if (msg.value < fee.nativeFee) revert InvalidMessageValue();

        _lzSend(dstEid, message, combinedOptions, fee, msg.sender, false);
        emit SharePricesSent(dstEid, vaultAddresses);
    }

    function requestSharePrices(
        uint32 dstEid,
        address[] calldata vaultAddresses,
        bytes calldata options,
        bytes calldata returnOptions,
        address rewardsDelegate
    )
        external
        payable
    {
        bytes memory message = MsgCodec.encodeVaultAddresses(ABA_TYPE, vaultAddresses, rewardsDelegate, returnOptions);
        bytes memory combinedOptions = _getCombinedOptions(dstEid, ABA_TYPE, options);

        MessagingFee memory fee = _quote(dstEid, message, combinedOptions);
        if (msg.value < fee.nativeFee) revert InvalidMessageValue();

        _lzSend(dstEid, message, combinedOptions, fee, msg.sender, false);
        emit SharePricesRequested(dstEid, vaultAddresses);
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////

    /// @notice Creates new TYPE_3 options
    function newOptions() public pure returns (bytes memory) {
        return abi.encodePacked(TYPE_3);
    }

    /// @notice Adds executor options to existing options
    function addExecutorLzReceiveOption(
        bytes memory _options,
        uint128 _gas,
        uint128 _value
    )
        public
        pure
        returns (bytes memory)
    {
        bytes memory option = _value == 0 ? abi.encodePacked(_gas) : abi.encodePacked(_gas, _value);

        return abi.encodePacked(
            _options,
            WORKER_ID,
            uint16(option.length + 1),
            uint8(1), // OPTION_TYPE_LZRECEIVE
            option
        );
    }

    /// @notice View function for fee estimation
    function estimateFees(
        uint32 dstEid,
        uint16 msgType,
        bytes calldata message,
        bytes calldata options
    )
        external
        view
        returns (uint256 nativeFee)
    {
        bytes memory combinedOptions = _getCombinedOptions(dstEid, msgType, options);
        return _quote(dstEid, message, combinedOptions).nativeFee;
    }

    ////////////////////////////////////////////////////////////////
    ///              LAYERZERO INTERFACE FUNCTIONS               ///
    ////////////////////////////////////////////////////////////////

    /// @inheritdoc ILayerZeroReceiver
    function allowInitializePath(Origin calldata origin) external view override returns (bool) {
        return peers[origin.srcEid] == origin.sender;
    }

    /// @inheritdoc ILayerZeroReceiver
    function nextNonce(uint32, bytes32) external pure override returns (uint64) {
        return 0;
    }

    /// @inheritdoc ILayerZeroReceiver
    function lzReceive(
        Origin calldata origin,
        bytes32 guid,
        bytes calldata message,
        address,
        bytes calldata
    )
        external
        payable
        override
    {
        if (msg.sender != address(endpoint)) revert OnlyEndpoint();

        if (_getPeerOrRevert(origin.srcEid) != origin.sender) {
            revert PeerNotSet(origin.srcEid);
        }

        if (processedMessages[guid]) revert MessageAlreadyProcessed();

        processedMessages[guid] = true;

        uint16 msgType = MsgCodec.decodeMsgType(message);

        if (msgType == AB_TYPE) {
            (, VaultReport[] memory reports,,) = MsgCodec.decodeVaultReports(message);

            oracle.updateSharePrices(reports[0].chainId, reports);
        } else if (msgType == ABA_TYPE) {
            _handleABAResponse(origin, message);
        }

        emit MessageProcessed(guid, message);
    }

    ////////////////////////////////////////////////////////////////
    ///                  INTERNAL FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    /// @notice Handles ABA pattern response messages
    function _handleABAResponse(Origin calldata origin, bytes calldata message) private {
        (, address[] memory vaultAddresses, address rewardsDelegate, uint256 start, uint256 length) =
            MsgCodec.decodeVaultAddresses(message);

        VaultReport[] memory reports = oracle.getSharePrices(vaultAddresses, rewardsDelegate);

        bytes memory returnOptions = message[start:start + length];
        bytes memory returnMessage = MsgCodec.encodeVaultReports(AB_TYPE, reports, returnOptions);

        bytes memory options = _getCombinedOptions(origin.srcEid, AB_TYPE, returnOptions);

        MessagingFee memory fee = _quote(origin.srcEid, returnMessage, options);

        if (address(this).balance < fee.nativeFee) revert InsufficientFunds();

        _lzSend(origin.srcEid, returnMessage, options, fee, address(this), true);
    }

    /// @notice Gets peer for endpoint or reverts
    function _getPeerOrRevert(uint32 _eid) internal view returns (bytes32) {
        bytes32 peer = peers[_eid];
        if (peer == bytes32(0)) revert PeerNotSet(_eid);
        return peer;
    }

    /// @notice Gets LayerZero message fee quote
    function _quote(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options
    )
        internal
        view
        returns (MessagingFee memory)
    {
        return endpoint.quote(
            MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, false), address(this)
        );
    }

    /// @notice Sends message through LayerZero
    function _lzSend(
        uint32 _dstEid,
        bytes memory _message,
        bytes memory _options,
        MessagingFee memory _fee,
        address _refundAddress,
        bool isResponse
    )
        internal
        returns (MessagingReceipt memory)
    {
        if (!isResponse && msg.value < _fee.nativeFee) revert InvalidMessageValue();
        if (isResponse && address(this).balance < _fee.nativeFee) revert InsufficientFunds();

        return endpoint.send{ value: _fee.nativeFee }(
            MessagingParams(_dstEid, _getPeerOrRevert(_dstEid), _message, _options, false), _refundAddress
        );
    }

    /// @notice Combines and validates options
    function _getCombinedOptions(
        uint32 _eid,
        uint16 _msgType,
        bytes memory _options
    )
        internal
        view
        returns (bytes memory)
    {
        bytes memory enforced = enforcedOptions[_eid][_msgType];

        if (enforced.length == 0) return _options;
        if (_options.length == 0) return enforced;
        if (_options.length < 2) revert InvalidOptions(_options);

        uint16 optionsType;
        assembly {
            optionsType := mload(add(_options, 2))
        }
        if (optionsType != TYPE_3) revert InvalidOptionType(optionsType);

        bytes memory result = new bytes(enforced.length + _options.length - 2);
        assembly {
            let enforcedLen := mload(enforced)
            let resultPtr := add(result, 32)
            let enforcedPtr := add(enforced, 32)
            let optionsPtr := add(add(_options, 34), 0)

            // Copy enforced options
            for { let i := 0 } lt(i, enforcedLen) { i := add(i, 32) } {
                mstore(add(resultPtr, i), mload(add(enforcedPtr, i)))
            }

            // Copy remaining options (excluding type)
            let remainingLen := sub(mload(_options), 2)
            for { let i := 0 } lt(i, remainingLen) { i := add(i, 32) } {
                mstore(add(add(resultPtr, enforcedLen), i), mload(add(optionsPtr, i)))
            }
        }
        return result;
    }

    /// @notice Validates TYPE_3 options
    function _assertOptionsType3(bytes memory _options) internal pure {
        if (_options.length < 2) revert InvalidOptions(_options);

        uint16 optionsType;
        assembly {
            optionsType := mload(add(_options, 2))
        }
        if (optionsType != TYPE_3) revert InvalidOptions(_options);
    }

    ////////////////////////////////////////////////////////////////
    ///                   FALLBACK FUNCTIONS                      ///
    ////////////////////////////////////////////////////////////////

    receive() external payable { }
}
