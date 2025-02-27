// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { MessagingFee } from "./ILayerZeroEndpointV2.sol";

/**
 * @title PriceReturnData
 * @notice Structure containing price data and metadata from oracle adapters
 * @param price Price normalized to WAD (1e18)
 * @param hadError Error flag for price retrieval
 * @param inUSD Whether price is denominated in USD
 */
struct PriceReturnData {
    uint240 price; // Price normalized to WAD (1e18)
    bool hadError; // Error flag - keeping consistent with your existing naming
    bool inUSD; // Price denomination
}

/**
 * @title VaultReport
 * @notice Structure containing vault share price information and metadata
 * @param sharePrice The current share price of the vault
 * @param lastUpdate Timestamp of the last update
 * @param chainId ID of the chain where the vault exists
 * @param rewardsDelegate Address to delegate rewards to
 * @param vaultAddress Address of the vault
 * @param asset Address of the vault's underlying asset
 * @param assetDecimals Decimals of the underlying asset
 */
struct VaultReport {
    uint256 sharePrice;
    uint64 lastUpdate;
    uint32 chainId;
    address rewardsDelegate;
    address vaultAddress;
    address asset;
    uint256 assetDecimals;
}

/**
 * @title ISharePriceRouter
 * @notice Interface for cross-chain ERC4626 vault share price router
 * @dev Combines functionality of price oracle adapters and router
 */
interface ISharePriceRouter {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AdapterAdded(address indexed adapter, uint256 indexed priority);
    event AdapterRemoved(address indexed adapter);
    event PriceStored(address indexed asset, uint256 price, uint256 timestamp);
    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);
    event SharePriceUpdated(uint32 indexed chainId, address indexed vault, uint256 sharePrice, address rewardsDelegate);
    event SequencerUpdated(address oldSequencer, address newSequencer);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the admin role identifier
    function ADMIN_ROLE() external view returns (uint256);

    /// @notice Get the updater role identifier
    function UPDATER_ROLE() external view returns (uint256);

    /// @notice Get the endpoint role identifier
    function ENDPOINT_ROLE() external view returns (uint256);

    /// @notice Check if the sequencer is valid (for L2s)
    function isSequencerValid() external view returns (bool);

    /// @notice Check if an asset is supported by any adapter
    function isSupportedAsset(address asset) external view returns (bool);

    /// @notice Generate a unique key for a vault's price data
    function getPriceKey(uint32 _chainId, address _vault) external pure returns (bytes32);

    /// @notice Get the price for an asset from the best available adapter
    function getPrice(address asset, bool inUSD) external view returns (uint256 price, uint256 errorCode);

    /// @notice Get the latest price from all adapters
    function getLatestPrice(
        address asset,
        bool inUSD
    )
        external
        view
        returns (uint256 price, uint256 timestamp, bool isUSD);

    /// @notice Get current share prices for multiple vaults
    function getSharePrices(
        address[] calldata vaultAddresses,
        address rewardsDelegate
    )
        external
        view
        returns (VaultReport[] memory);

    /// @notice Get latest share price for a specific vault
    function getLatestSharePrice(
        address _vaultAddress,
        address _dstAsset
    )
        external
        returns (uint256 sharePrice, uint64 timestamp);

    /// @notice Get latest share price report for a specific vault
    function getLatestSharePriceReport(
        uint32 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (VaultReport memory);

    /// @notice Calculate share price for a vault in terms of a destination asset
    function calculateSharePrice(
        address _vaultAddress,
        address _dstAsset
    )
        external
        view
        returns (uint256 sharePrice, uint64 timestamp);

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Grant a role to an account
    function grantRole(address account, uint256 role) external;

    /// @notice Revoke a role from an account
    function revokeRole(address account, uint256 role) external;

    /// @notice Add a new oracle adapter
    function addAdapter(address adapter, uint256 priority) external;

    /// @notice Remove an oracle adapter
    function removeAdapter(address adapter) external;

    /// @notice Set the category for an asset
    function setAssetCategory(address asset, uint8 category) external;

    /// @notice Set the sequencer uptime feed address
    function setSequencer(address _sequencer) external;

    /// @notice Update price for an asset
    function updatePrice(address asset, bool inUSD) external;

    /// @notice Update share prices from another chain
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata _reports) external;

    /// @notice Convert a stored price to a different denomination
    function convertStoredPrice(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    )
        external
        view
        returns (uint256 price, uint64 timestamp);

    /// @notice Notify router of feed removal
    function notifyFeedRemoval(address asset) external;
}
