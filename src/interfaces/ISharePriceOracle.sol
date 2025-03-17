// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { MessagingFee } from "./ILayerZeroEndpointV2.sol";

/**
 * @title ISharePriceOracle
 * @notice Interface for cross-chain ERC4626 vault share price oracle
 * @dev Combines functionality of price oracle adapters and router
 */
interface ISharePriceOracle {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS 
    //////////////////////////////////////////////////////////////*/
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

    /// @notice Configuration for local assets (USDC, WETH, WBTC)
    struct LocalAssetConfig {
        address priceFeed; // Priority-ordered price feeds
        bool inUSD; // Whether price should be in USD
        address adaptor; // Adapter address
    }

    /// @notice Enhanced stored share price data
    struct StoredSharePrice {
        uint248 sharePrice; // Share price in terms of local asset
        uint8 decimals; // Decimals of the local asset
        uint64 timestamp;
        address asset; // The local asset address (USDC, WETH, WBTC)
    }

    struct StoredAssetPrice {
        uint256 price;
        uint64 timestamp;
        bool inUSD;
    }
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceStored(address indexed asset, uint256 price, uint256 timestamp, bool inUSD);
    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);
    event SharePriceUpdated(
        uint32 indexed srcChainId, address indexed vault, uint256 sharePrice, uint256 assetPrice, uint64 timestamp
    );
    event SequencerSet(address indexed oldSequencer, address indexed sequencer);
    event CrossChainAssetMapped(uint32 indexed srcChainId, address indexed srcAsset, address indexed localAsset);
    event LocalAssetConfigured(address indexed asset, uint8 priority, address priceFeed, bool inUSD);
    event LocalAssetRemoved(address indexed asset);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Configure a price feed for a local asset with priority level
     * @param _localAsset The local asset to configure (USDC, WETH, WBTC)
     * @param _priority Priority level (0 = highest priority)
     * @param _priceFeed Array of price feed addresses in priority order
     * @param _isUSD Whether price should be in USD
     */
    function setLocalAssetConfig(
        address _localAsset,
        address adapter,
        address _priceFeed,
        uint8 _priority,
        bool _isUSD
    )
        external;

    /**
     * @notice Grants a role to an account
     * @dev Only callable by admin
     * @param account Address to receive the role
     * @param role Role identifier to grant
     */
    function grantRole(address account, uint256 role) external;

    /**
     * @notice Revokes a role from an account
     * @dev Only callable by admin
     * @param account Address to lose the role
     * @param role Role identifier to revoke
     */
    function revokeRole(address account, uint256 role) external;

    /**
     * @notice Sets the sequencer uptime feed address
     * @dev Only callable by admin
     * @param _sequencer The new sequencer uptime feed address
     */
    function setSequencer(address _sequencer) external;

    /**
     * @notice Sets the mapping between a cross-chain asset and its local equivalent
     * @dev Only callable by admin. Maps assets from other chains to their Base equivalents
     * @param _srcChainId The source chain ID
     * @param _srcAsset The asset address on the source chain
     * @param _localAsset The equivalent asset address on Base
     */
    function setCrossChainAssetMapping(uint32 _srcChainId, address _srcAsset, address _localAsset) external;

    /*//////////////////////////////////////////////////////////////
                        ENDPOINT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Updates share prices from another chain
     * @dev Only callable by endpoint. Maps remote assets to local ones and stores prices
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata reports) external;

    /*//////////////////////////////////////////////////////////////
                           ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Notify router of feed removal
    function notifyFeedRemoval(address asset) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the admin role identifier
    function ADMIN_ROLE() external view returns (uint256);

    /// @notice Get the updater role identifier
    function ADAPTER_ROLE() external view returns (uint256);

    /// @notice Get the endpoint role identifier
    function ENDPOINT_ROLE() external view returns (uint256);

    function isSupportedAsset(address asset) external view returns (bool);

    /**
     * @notice Checks if the sequencer is valid (for L2s)
     * @dev Returns true for L1s or if no sequencer check needed
     * @return True if the sequencer is valid
     */
    function isSequencerValid() external view returns (bool);

    /**
     * @notice Generates a unique key for storing share prices
     * @dev Uses keccak256 hash of chain ID and vault address
     * @param _chainId Chain ID
     * @param _vaultAddress Vault address
     * @return The unique key as bytes32
     */
    function getPriceKey(uint32 _chainId, address _vaultAddress) external pure returns (bytes32);

    /**
     * @notice Gets the latest price for an asset
     * @param _asset The asset address
     * @param _inUSD Whether the price should be in USD
     * @return price The latest price
     * @return hadError Whether the price retrieval had an error
     */
    function getLatestAssetPrice(address _asset, bool _inUSD) external view returns (uint256 price, bool hadError);

    /**
     * @notice Gets the local asset and its decimals for a cross-chain asset mapped
     * @param _srcChainId The source chain id
     * @param _srcAsset The source asset address
     * @return localAsset The local asset address
     * @return localDecimals The local asset decimals
     */
    function getLocalAsset(
        uint32 _srcChainId,
        address _srcAsset
    )
        external
        view
        returns (address localAsset, uint8 localDecimals);

    function getPrice(address asset, bool inUSD) external view returns (uint256 price, bool hadError);

    /**
     * @notice Gets share prices for multiple vaults
     * @dev Returns array of vault reports with current prices
     * @param vaultAddresses Array of vault addresses
     * @param rewardsDelegate Address of the rewards delegate
     * @return reports Array of vault reports
     */
    function getSharePrices(
        address[] calldata vaultAddresses,
        address rewardsDelegate
    )
        external
        view
        returns (VaultReport[] memory reports);

    /**
     * @notice Gets the latest share price for a vault
     * @dev Tries multiple methods to get the price in order:
     *      1. For local vaults: Try current calculation through vault.convertToAssets
     *      2. For cross-chain vaults:
     *         a. Try stored share price with conversion if needed
     *         b. Try cross-chain rate with local equivalent asset
     * @param _srcChainId Chain ID where the vault exists
     * @param _vaultAddress Address of the vault
     * @param _dstAsset Address of the destination asset (local chain)
     * @return sharePrice Current share price in terms of _dstAsset (never returns 0)
     * @return timestamp Timestamp of the price data
     */
    function getLatestSharePrice(
        uint32 _srcChainId,
        address _vaultAddress,
        address _dstAsset
    )
        external
        view
        returns (uint256 sharePrice, uint64 timestamp);

    /**
     * @notice Get latest share price report for a specific vault
     * @dev Returns the stored report for a vault from a specific chain
     * @param _srcChainId The source chain ID
     * @param _vaultAddress The vault address
     * @return The vault report containing share price and metadata
     */
    function getLatestSharePriceReport(
        uint32 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (VaultReport memory);

    /**
     * @notice Updates the price for the given assets
     * @param assets An array assets to update the prices for
     * @return bool if the prices were updated
     */
    function batchUpdatePrices(address[] calldata assets, bool[] calldata inUSD) external returns (bool);
}
