// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {
    ISharePriceOracle,
    PriceFeedInfo,
    PriceDenomination,
    VaultReport,
    ChainlinkResponse
} from "./interfaces/ISharePriceOracle.sol";
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20Metadata } from "./interfaces/IERC20Metadata.sol";
import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";

import { ChainlinkLib } from "./libs/ChainlinkLib.sol";
import { VaultLib } from "./libs/VaultLib.sol";
import { PriceConversionLib } from "./libs/PriceConversionLib.sol";

contract SharePriceOracle is ISharePriceOracle, OwnableRoles {
    using ChainlinkLib for address;
    using VaultLib for IERC4626;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error InvalidRole();
    error InvalidChainId(uint32 receivedChainId);
    error InvalidReporter();
    error PriceFeedNotFound();
    error InvalidFeed();
    error InvalidPrice();
    error ExceedsMaxReports();
    error InvalidHeartbeat();

    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for LayerZero endpoint
    uint256 public constant ENDPOINT_ROLE = _ROLE_1;

    /// @notice Staleness tolerance for share prices
    uint256 public constant SHARE_PRICE_STALENESS_TOLERANCE = 8 hours;

    uint256 public constant MAX_REPORTS = 10;

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Chain ID this oracle is deployed on
    uint32 public immutable override chainId;

    address public immutable ETH_USD_FEED;

    /// @notice ChainLink price feed sequencer
    /// This should be address 0 if not an L2
    /// addresses: https://docs.chain.link/data-feeds/l2-sequencer-feeds#available-networks
    address public sequencer;

    /// @notice LayerZero endpoint address
    address private lzEndpoint;

    /// @notice Mapping from price key to struct vault report
    /// @dev Key is keccak256(abi.encodePacked(srcChainId, vaultAddress))
    mapping(bytes32 => VaultReport) public sharePrices;

    /// @notice Mapping from Chainlink feed address to chain ID to asset address
    /// 1st level key: chain Id
    /// 2nd level key: asset address
    /// Value: Chainlink feed address
    mapping(uint32 => mapping(address => PriceFeedInfo)) public priceFeeds;

    ////////////////////////////////////////////////////////////////
    ///                       MODIFIERS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Restricts function access to the LayerZero endpoint
    modifier onlyEndpoint() {
        _checkRoles(ENDPOINT_ROLE);
        _;
    }

    /// @notice Restricts function access to admin role
    modifier onlyAdmin() {
        _checkRoles(ADMIN_ROLE);
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                     CONSTRUCTOR                           ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Initializes the oracle with chain ID and admin address
     * @param _admin Address of the initial admin
     */
    constructor(address _admin, address _ethUsdFeed) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_ethUsdFeed == address(0)) revert ZeroAddress();

        chainId = uint32(block.chainid);
        ETH_USD_FEED = _ethUsdFeed;
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    ////////////////////////////////////////////////////////////////
    ///                    ADMIN FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Sets the sequencer
     * This should be address 0 if not an L2
     * @param _newSequencer New endpoint address
     */
    function setSequencer(address _newSequencer) external onlyAdmin {
        address oldSequencer = sequencer;
        sequencer = _newSequencer;
        emit SequencerUpdated(oldSequencer, _newSequencer);
    }

    /**
     * @notice Sets the LayerZero endpoint address
     * @param _endpoint New endpoint address
     */
    function setLzEndpoint(address _endpoint) external onlyAdmin {
        if (_endpoint == address(0)) revert ZeroAddress();
        address oldEndpoint = lzEndpoint;
        _removeRoles(oldEndpoint, ENDPOINT_ROLE);
        lzEndpoint = _endpoint;
        _grantRoles(_endpoint, ENDPOINT_ROLE);
        emit LzEndpointUpdated(oldEndpoint, _endpoint);
        emit RoleGranted(_endpoint, ENDPOINT_ROLE);
    }

    /**
     *
     *  @notice Sets the price feed for a specific chain and asset
     * @param _chainId Chain ID
     * @param _asset Asset address
     * @param _priceFeed Price feed info including feed address, denomination and heartbeat
     */
    function setPriceFeed(uint32 _chainId, address _asset, PriceFeedInfo calldata _priceFeed) external onlyAdmin {
        if (_chainId == 0) revert InvalidChainId(_chainId);
        if (_asset == address(0)) revert ZeroAddress();
        if (_priceFeed.feed == address(0)) revert ZeroAddress();
        if (_priceFeed.heartbeat == 0) revert InvalidHeartbeat();

        ChainlinkResponse memory response = _priceFeed.feed.getPrice(sequencer, _priceFeed.heartbeat);
        if (response.price == 0) revert InvalidFeed();

        priceFeeds[_chainId][_asset] = _priceFeed;

        emit PriceFeedSet(_chainId, _asset, _priceFeed.feed);
    }

    /**
     * @notice Grants a role to an account
     * @param account Address to grant the role to
     * @param role Role identifier to grant
     */
    function grantRole(address account, uint256 role) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _grantRoles(account, role);
        emit RoleGranted(account, role);
    }

    /**
     * @notice Revokes a role from an account
     * @param account Address to revoke the role from
     * @param role Role identifier to revoke
     */
    function revokeRole(address account, uint256 role) external override onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL FUNCTIONS                       ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Updates share prices from another chain
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata reports) external override onlyEndpoint {
        if (_srcChainId == chainId) revert InvalidChainId(_srcChainId);

        uint256 len = reports.length;
        bytes32 key;

        unchecked {
            for (uint256 i; i < len; ++i) {
                VaultReport calldata report = reports[i];
                if (report.chainId != _srcChainId) {
                    revert InvalidChainId(report.chainId);
                }
                if (report.sharePrice == 0) revert InvalidPrice();
                key = getPriceKey(_srcChainId, report.vaultAddress);
                sharePrices[key] = report;

                emit SharePriceUpdated(_srcChainId, report.vaultAddress, report.sharePrice, report.rewardsDelegate);
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                     INTERNAL FUNCTIONS                    ///
    ////////////////////////////////////////////////////////////////

    /**
     * @notice Gets share price for a vault on the same chain as the oracle
     * @param _vaultAddress Address of the vault
     * @param _dstAsset Asset to get the price in
     * @return sharePrice Current share price in terms of _dstAsset
     * @return timestamp Timestamp of the price data
     */
    function _getDstSharePrice(
        address _vaultAddress,
        address _dstAsset
    )
        internal
        view
        returns (uint256 sharePrice, uint64 timestamp)
    {
        VaultReport memory report = _getVaultSharePrice(
            _vaultAddress,
            address(0) // Not needed for this function
        );

        if (report.sharePrice == 0) {
            return (0, 0);
        }

        if (report.asset == _dstAsset) {
            return (report.sharePrice, report.lastUpdate);
        }

        // Convert price but ignore returned timestamp from conversion
        (sharePrice, timestamp) = _convertAssetPrice(report.sharePrice, chainId, report.asset, _dstAsset, report);

        // If price is 0 (stale/invalid), return (0,0)
        if (sharePrice == 0) {
            return (0, 0);
        }

        return (sharePrice, report.lastUpdate);
    }

    /**
     * @notice Gets vault share price information
     * @param _vaultAddress Address of the vault
     * @param _rewardsDelegate Address to delegate rewards to
     * @return report VaultReport containing price and metadata
     */
    function _getVaultSharePrice(
        address _vaultAddress,
        address _rewardsDelegate
    )
        internal
        view
        returns (VaultReport memory report)
    {
        return VaultLib.getVaultSharePrice(_vaultAddress, _rewardsDelegate, chainId);
    }

    /**
     * @notice Gets share price for a vault on a different chain
     * @param _srcChainId Source chain ID
     * @param _vaultAddress Vault address
     * @param _dstAsset Asset to get the price in
     * @return sharePrice Current share price in terms of _dstAsset
     * @return timestamp Timestamp of the price data
     */
    function _getSrcSharePrice(
        uint32 _srcChainId,
        address _vaultAddress,
        address _dstAsset
    )
        internal
        view
        returns (uint256 sharePrice, uint64 timestamp)
    {
        VaultReport memory report = getLatestSharePriceReport(_srcChainId, _vaultAddress);

        unchecked {
            if (report.lastUpdate + SHARE_PRICE_STALENESS_TOLERANCE < block.timestamp) {
                return (0, 0);
            }
        }

        // Convert price but ignore returned timestamp from conversion
        (sharePrice,) = _convertAssetPrice(report.sharePrice, _srcChainId, report.asset, _dstAsset, report);

        // Return the oracle's last update time instead
        return (sharePrice, report.lastUpdate);
    }

    /**
     * @notice Converts an amount from one asset to another using their respective prices
     * @param amount Amount to convert
     * @param _srcChainId Source chain ID
     * @param _srcAsset Source asset address
     * @param _dstAsset Destination asset address
     * @param _report VaultReport containing price and metadata
     * @return price The converted price in terms of the destination asset
     * @return timestamp The earlier timestamp between source and destination prices
     */
    function _convertAssetPrice(
        uint256 amount,
        uint32 _srcChainId,
        address _srcAsset,
        address _dstAsset,
        VaultReport memory _report
    )
        internal
        view
        returns (uint256 price, uint64 timestamp)
    {
        PriceFeedInfo memory srcFeed = priceFeeds[_srcChainId][_srcAsset];
        PriceFeedInfo memory dstFeed = priceFeeds[chainId][_dstAsset];

        if (srcFeed.feed == address(0) || dstFeed.feed == address(0)) {
            return (0, 0);
        }

        // Get the price from PriceConversionLib
        price = PriceConversionLib.convertFullPrice(
            PriceConversionLib.ConversionParams({
                amount: amount,
                srcChainId: _srcChainId,
                chainId: chainId,
                srcAsset: _srcAsset,
                dstAsset: _dstAsset,
                ethUsdFeed: ETH_USD_FEED,
                sequencer: sequencer,
                srcFeed: srcFeed,
                dstFeed: dstFeed,
                srcReport: _report
            })
        );

        // If price conversion failed or returned 0, return (0,0)
        if (price == 0) {
            return (0, 0);
        }

        timestamp = _report.lastUpdate;
        return (price, timestamp);
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Gets current share prices for multiple vaults
     * @param vaultAddresses Array of vault addresses
     * @param rewardsDelegate Address to delegate rewards to
     * @return VaultReport[] Array of vault reports
     */
    function getSharePrices(
        address[] calldata vaultAddresses,
        address rewardsDelegate
    )
        external
        view
        override
        returns (VaultReport[] memory)
    {
        uint256 len = vaultAddresses.length;
        if (len > MAX_REPORTS) revert ExceedsMaxReports();

        VaultReport[] memory reports = new VaultReport[](len);

        unchecked {
            for (uint256 i; i < len; ++i) {
                reports[i] = _getVaultSharePrice(vaultAddresses[i], rewardsDelegate);
            }
        }
        return reports;
    }

    /**
     * @notice Gets latest share price for a specific vault
     * @param _srcChainId Source chain ID
     * @param _vaultAddress Vault address
     * @return vaultReport The latest vault report for that key
     */
    function getLatestSharePriceReport(
        uint32 _srcChainId,
        address _vaultAddress
    )
        public
        view
        override
        returns (VaultReport memory vaultReport)
    {
        bytes32 key = getPriceKey(_srcChainId, _vaultAddress);
        return vaultReport = sharePrices[key];
    }

    /**
     * @notice Gets latest share price from the desired vault in requested asset terms
     * THIS WILL NOT REVERT, IF FAIL RETURNS (0, 0)
     * THE EARLIEST PRICE FEED TIMESTAMP WILL BE RETURNED
     * I DON'T VALIDATE PRICE FEED TIMESTAMP, THIS SHOULD BE
     * FOR THE CALLER TO DO
     * @param _srcChainId Source chain ID
     * @param _vaultAddress Vault address
     * @param _dstAsset Asset to get the price in
     * @return sharePrice in requested asset terms
     * @return timestamp Price timestamp
     */
    function getLatestSharePrice(
        uint32 _srcChainId,
        address _vaultAddress,
        address _dstAsset
    )
        external
        view
        override
        returns (uint256 sharePrice, uint64 timestamp)
    {
        if (_srcChainId == chainId) {
            return _getDstSharePrice(_vaultAddress, _dstAsset);
        }
        return _getSrcSharePrice(_srcChainId, _vaultAddress, _dstAsset);
    }

    /**
     * @notice Generates a unique key for a vault's price data
     * @param _srcChainId Source chain ID
     * @param _vault Vault address
     * @return bytes32 The generated key
     */
    function getPriceKey(uint32 _srcChainId, address _vault) public pure override returns (bytes32) {
        return keccak256(abi.encode(_srcChainId, _vault));
    }

    /**
     * @notice Checks if an account has a specific role
     * @param account Address to check
     * @param role Role to check for
     * @return bool True if account has the role
     */
    function hasRole(address account, uint256 role) public view override returns (bool) {
        return hasAnyRole(account, role);
    }

    /**
     * @notice Gets all roles assigned to an account
     * @param account Address to check
     * @return uint256 Bitmap of assigned roles
     */
    function getRoles(address account) external view override returns (uint256) {
        return rolesOf(account);
    }
}
