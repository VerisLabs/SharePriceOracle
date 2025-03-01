// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {ISharePriceRouter, PriceReturnData, VaultReport} from "./interfaces/ISharePriceRouter.sol";
import {BaseOracleAdapter} from "./libs/base/BaseOracleAdapter.sol";
import {IChainlink} from "./interfaces/chainlink/IChainlink.sol";
import {IChainlink} from "./interfaces/chainlink/IChainlink.sol";

/**
 * @title SharePriceRouter
 * @notice A multi-adapter oracle system that supports multiple price feeds and fallback mechanisms
 * @dev This contract manages multiple oracle adapters and provides unified price conversion
 */
contract SharePriceRouter is OwnableRoles {
    using FixedPointMathLib for uint256;

    /* Errors */
    // Access control errors
    error InvalidRole();

    // Asset configuration errors
    error InvalidAsset(address asset);
    error InvalidPriceType();
    error InvalidPriceFeed();
    error AssetNotConfigured(address asset);

    // Price-related errors
    error NoValidPrice();
    error StalePrice();
    error PriceConversionFailed();

    // Chain and sequencer errors
    error InvalidChainId();
    error SequencerUnavailable();

    // Validation errors
    error ZeroAddress();
    error InvalidReportLength();
    error ExceedsMaxReports();

    // Adapter errors
    error AdapterNotFound();
    error AdapterAlreadyExists();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AdapterAdded(address indexed adapter);
    event AdapterRemoved(address indexed adapter);
    event PriceStored(address indexed asset, uint256 price, uint256 timestamp);
    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);
    event SharePriceUpdated(
        uint32 indexed srcChainId,
        address indexed vault,
        uint256 sharePrice,
        uint256 assetPrice,
        uint64 timestamp
    );
    event SequencerSet(address indexed sequencer);
    event FallbackPriceUsed(
        address indexed vaultAddress,
        address indexed asset,
        uint256 sharePrice,
        string reason
    );
    event CrossChainAssetMapped(
        uint32 indexed srcChainId,
        address indexed srcAsset,
        address indexed localAsset
    );
    event NoCrossChainAssetMapping(
        uint32 indexed srcChainId,
        address indexed srcAsset
    );
    event LocalAssetConfigured(
        address indexed asset,
        uint8 priority,
        address priceFeed,
        bool inUSD
    );
    event PriceConverted(
        address indexed srcAsset,
        address indexed dstAsset,
        uint256 srcPrice,
        uint256 dstPrice,
        uint64 timestamp
    );
    event PriceFeedFailed(
        address indexed asset,
        address indexed feed,
        string reason
    );
    event SharePriceStored(
        address indexed vault,
        address indexed asset,
        uint256 sharePrice,
        uint256 assetPrice,
        uint64 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    /// @notice Role identifier for price updater capabilities
    uint256 public constant UPDATER_ROLE = _ROLE_1;
    /// @notice Role identifier for endpoint capabilities
    uint256 public constant ENDPOINT_ROLE = _ROLE_2;
    /// @notice Maximum number of reports that can be processed in a single update
    uint256 public constant MAX_REPORTS = 10;
    /// @notice Maximum staleness for stored prices
    uint256 public constant PRICE_STALENESS_THRESHOLD = 24 hours;
    /// @notice Minimum valid price threshold
    uint256 public constant MIN_PRICE_THRESHOLD = 1e2; // 0.0000000001 in 18 decimals
    /// @notice Grace period after sequencer is back up
    uint256 public constant GRACE_PERIOD_TIME = 3600; // 1 hour

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Chain ID this oracle is deployed on
    /// @dev Immutable value set in constructor
    uint32 public immutable chainId;

    /// @notice USDC token address
    /// @dev Immutable value set in constructor
    address public immutable USDC;

    /// @notice WBTC token address
    /// @dev Immutable value set in constructor
    address public immutable WBTC;

    /// @notice WETH token address
    /// @dev Immutable value set in constructor
    address public immutable WETH;

    /// @notice Sequencer uptime feed address
    /// @dev Used to check L2 sequencer status
    address public sequencer;

    /// @notice Configuration for local assets (USDC, WETH, WBTC)
    struct LocalAssetConfig {
        address priceFeed; // Priority-ordered price feeds
        bool inUSD; // Whether price should be in USD
    }

    /// @notice Enhanced stored share price data
    struct StoredSharePrice {
        uint248 sharePrice; // Share price in terms of local asset
        uint8 decimals; // Decimals of the local asset
        address asset; // The local asset address (USDC, WETH, WBTC)
        uint64 timestamp; // When this data was last updated
        bool inUSD; // Whether the price is in USD
        uint256 assetPrice; // Price of the local asset at update time
    }

    struct StoredAssetPrice {
        uint256 price;
        uint64 timestamp;
        bool inUSD;
    }

    /// @notice Maps local assets to their price feed configurations
    /// localAsset address, adapterPriority, localAssetConfig
    mapping(address => mapping(uint8 => LocalAssetConfig))
        public localAssetConfigs;

    /// @notice Maps vault address to its last stored share price data
    mapping(address => StoredSharePrice) public storedSharePrices;

    /// @notice Maps asset address to its last stored price data
    mapping(address => StoredAssetPrice) public storedAssetPrices;

    /// @notice Mapping of cross-chain assets to their local equivalents
    /// @dev key = keccak256(srcChainId, srcAsset)
    mapping(bytes32 => address) public crossChainAssetMap;

    /// @notice Mapping from price key to struct vault report
    /// @dev Key is keccak256(abi.encodePacked(srcChainId, vaultAddress))
    mapping(bytes32 => VaultReport) public sharePrices;

    /// @notice Mapping of adapter address to its index in oracleAdapters array plus 1 (0 means not in array)
    mapping(address => uint256) private adapterIndices;

    /// @notice Array of oracle adapter addresses
    mapping(address => uint8) public assetAdapterPriority;

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
        _checkOwnerOrRoles(ADMIN_ROLE);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _admin, address _usdc, address _wbtc, address _weth) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_wbtc == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();

        chainId = uint32(block.chainid);
        USDC = _usdc;
        WBTC = _wbtc;
        WETH = _weth;

        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

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
        uint8 _priority,
        address _priceFeed,
        bool _isUSD
    ) external onlyAdmin {
        if (_localAsset == address(0)) revert ZeroAddress();
        if (_priceFeed == address(0)) revert ZeroAddress();

        localAssetConfigs[_localAsset][_priority] = LocalAssetConfig({
            priceFeed: _priceFeed,
            inUSD: _isUSD
        });

        // Update highest priority if needed
        if (_priority > assetAdapterPriority[_localAsset]) {
            assetAdapterPriority[_localAsset] = _priority;
        }

        emit LocalAssetConfigured(_localAsset, _priority, _priceFeed, _isUSD);
    }

    /**
     * @notice Grants a role to an account
     * @dev Only callable by admin
     * @param account Address to receive the role
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
     * @dev Only callable by admin
     * @param account Address to lose the role
     * @param role Role identifier to revoke
     */
    function revokeRole(address account, uint256 role) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }

    /**
     * @notice Sets the sequencer uptime feed address
     * @dev Only callable by admin
     * @param _sequencer The new sequencer uptime feed address
     */
    function setSequencer(address _sequencer) external onlyAdmin {
        address oldSequencer = sequencer;
        sequencer = _sequencer;
        emit SequencerSet(_sequencer);
    }

    /**
     * @notice Sets the mapping between a cross-chain asset and its local equivalent
     * @dev Only callable by admin. Maps assets from other chains to their Base equivalents
     * @param _srcChainId The source chain ID
     * @param _srcAsset The asset address on the source chain
     * @param _localAsset The equivalent asset address on Base
     */
    function setCrossChainAssetMapping(
        uint32 _srcChainId,
        address _srcAsset,
        address _localAsset
    ) external onlyAdmin {
        if (_srcChainId == chainId) revert InvalidChainId();
        if (_srcAsset == address(0) || _localAsset == address(0))
            revert ZeroAddress();

        bytes32 key = keccak256(abi.encodePacked(_srcChainId, _srcAsset));
        crossChainAssetMap[key] = _localAsset;

        emit CrossChainAssetMapped(_srcChainId, _srcAsset, _localAsset);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the sequencer is valid (for L2s)
     * @dev Returns true for L1s or if no sequencer check needed
     * @return True if the sequencer is valid
     */
    function isSequencerValid() external view returns (bool) {
        return _isSequencerValid();
    }

    /**
     * @notice Generates a unique key for storing share prices
     * @dev Uses keccak256 hash of chain ID and vault address
     * @param _chainId Chain ID
     * @param _vaultAddress Vault address
     * @return The unique key as bytes32
     */
    function getPriceKey(
        uint32 _chainId,
        address _vaultAddress
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId, _vaultAddress));
    }

    /**
     * @notice Get a fresh price for an asset from configured price feeds
     * @param _asset Asset to get price for
     * @return price Latest price
     * @return timestamp Timestamp of the price
     */
    function _getPrice(
        address _asset
    ) internal view returns (uint256 price, uint64 timestamp, bool inUSD) {
        uint8 assetPriority = assetAdapterPriority[_asset];
        if (assetPriority == 0) revert AssetNotConfigured(_asset);

        // Try each configuration by priority
        for (uint8 i = 0; i <= assetPriority; i++) {
            LocalAssetConfig memory config = localAssetConfigs[_asset][i];
            try
                BaseOracleAdapter(config.priceFeed).getPrice(
                    _asset,
                    config.inUSD
                )
            returns (PriceReturnData memory priceData) {
                if (!priceData.hadError && priceData.price > 0) {
                    return (
                        priceData.price,
                        uint64(block.timestamp),
                        config.inUSD
                    );
                }
            } catch {}
        }
    }

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
    ) external view returns (VaultReport[] memory reports) {
        uint256 len = vaultAddresses.length;
        reports = new VaultReport[](len);

        for (uint256 i = 0; i < len; i++) {
            address vaultAddress = vaultAddresses[i];
            IERC4626 vault = IERC4626(vaultAddress);

            // Get vault details
            address asset = vault.asset();
            uint8 assetDecimals = _getAssetDecimals(asset);

            // Calculate actual share price - how many assets you get for a normalized amount of shares
            uint256 sharePrice = vault.convertToAssets(10 ** assetDecimals);

            reports[i] = VaultReport({
                chainId: chainId,
                vaultAddress: vaultAddress,
                asset: asset,
                assetDecimals: assetDecimals,
                sharePrice: sharePrice,
                lastUpdate: uint64(block.timestamp),
                rewardsDelegate: rewardsDelegate
            });
        }
    }

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
    ) external view returns (uint256 sharePrice, uint64 timestamp) {
        // Get stored share price data
        StoredSharePrice memory stored = storedSharePrices[_vaultAddress];
        // no need for sharePrice > 0 already cheched on updateSharePrices
        // Convert stored price to destination asset
        (sharePrice, timestamp) = _convertPrice(
            stored.sharePrice,
            stored.asset,
            _dstAsset,
            stored.decimals,
            _getAssetDecimals(_dstAsset)
        );

        return (sharePrice, timestamp);
    }

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
    ) external view returns (VaultReport memory) {
        bytes32 key = getPriceKey(_srcChainId, _vaultAddress);
        return sharePrices[key];
    }

    /**
     * @notice Updates an asset price
     * @dev Stores the price and Timestamp
     */
    function _updatePrice(address asset) internal returns (bool) {
        (uint256 price, uint64 timestamp, bool isUsd) = _getPrice(asset);
        if (price == 0) revert NoValidPrice();
        storedAssetPrices[asset] = StoredAssetPrice({
            price: price,
            timestamp: timestamp,
            inUSD: isUsd
        });
        emit PriceStored(asset, price, timestamp);
        return true;
    }

    function batchUpdatePrices(
        address[] calldata assets
    ) external returns (bool) {
        for (uint256 i = 0; i < assets.length; i++) {
            _updatePrice(assets[i]);
        }
        return true;
    }

    /**
     * @notice Updates share prices from another chain
     * @dev Only callable by endpoint. Maps remote assets to local ones and stores prices
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(
        uint32 _srcChainId,
        VaultReport[] calldata reports
    ) external onlyEndpoint {
        if (_srcChainId == chainId) revert InvalidChainId();
        if (reports.length == 0) return;
        if (reports.length > MAX_REPORTS) revert ExceedsMaxReports();

        for (uint256 i = 0; i < reports.length; i++) {
            VaultReport calldata report = reports[i];

            // Basic validation
            if (report.chainId != _srcChainId) revert InvalidChainId();
            if (report.sharePrice == 0) revert NoValidPrice();
            if (report.asset == address(0)) revert ZeroAddress();

            // Store the original report
            bytes32 key = getPriceKey(_srcChainId, report.vaultAddress);
            sharePrices[key] = report;

            (address localAsset, uint8 localDecimals) = getLocalAsset(
                _srcChainId,
                report.asset
            );

            // Get stored price instead of calling oracle
            StoredAssetPrice memory storedPrice = storedAssetPrices[localAsset];

            // Check if we have a valid stored price
            if (storedPrice.price == 0 || _isStale(storedPrice.timestamp))
                revert NoValidPrice();

            storedSharePrices[report.vaultAddress] = StoredSharePrice({
                sharePrice: uint248(report.sharePrice),
                decimals: localDecimals,
                asset: localAsset,
                timestamp: uint64(block.timestamp),
                inUSD: storedPrice.inUSD,
                assetPrice: storedPrice.price
            });

            emit SharePriceUpdated(
                _srcChainId,
                report.vaultAddress,
                report.sharePrice,
                storedPrice.price,
                uint64(block.timestamp)
            );
        }
    }

    /**
     * @notice Converts a price from one asset to another using stored prices
     * @param _price Price to convert
     * @param _srcAsset Source asset address
     * @param _dstAsset Destination asset address
     * @param _srcDecimals Source asset decimals
     * @param _dstDecimals Destination asset decimals
     * @return convertedPrice Converted price
     * @return timestamp Timestamp of the conversion
     */
    function _convertPrice(
        uint256 _price,
        address _srcAsset,
        address _dstAsset,
        uint8 _srcDecimals,
        uint8 _dstDecimals
    ) internal view returns (uint256 convertedPrice, uint64 timestamp) {
        // Get prices for both assets
        (uint256 srcPrice, uint64 srcTime, bool srcIsUsd) = _getPrice(
            _srcAsset
        );
        (uint256 dstPrice, uint64 dstTime, bool dstIsUsd) = _getPrice(
            _dstAsset
        );

        if (srcPrice == 0) {
            // Try to get the stored price
            StoredAssetPrice memory storedPrice = storedAssetPrices[_srcAsset];
            srcPrice = storedPrice.price;
            srcIsUsd = storedPrice.inUSD;
            srcTime = storedPrice.timestamp;
        }

        if (dstPrice == 0) {
            // Try to get the stored price
            StoredAssetPrice memory storedPrice = storedAssetPrices[_dstAsset];
            dstPrice = storedPrice.price;
            dstIsUsd = storedPrice.inUSD;
            dstTime = storedPrice.timestamp;
        }

        // First normalize the input price to 18 decimals for consistent math
        (uint256 normalizedPrice, ) = _adjustDecimals(_price, _srcDecimals, 18);

        // Apply price conversion based on asset types (with normalized decimals)
        if (srcIsUsd && !dstIsUsd) {
            // Source is USD, destination is not (e.g., converting USD to ETH)
            // Need to divide by destination price (USD/ETH)
            convertedPrice = FixedPointMathLib.mulDiv(
                normalizedPrice,
                1,
                dstPrice
            );
        } else if (!srcIsUsd && dstIsUsd) {
            // Destination is USD, source is not (e.g., converting ETH to USD)
            // Need to multiply by source price (ETH/USD)
            convertedPrice = FixedPointMathLib.mulDiv(
                normalizedPrice,
                srcPrice,
                1
            );
        } else {
            // USD to USD or non-USD to non-USD
            // Need to multiply by source price and divide by destination price
            convertedPrice = FixedPointMathLib.mulDiv(
                normalizedPrice,
                srcPrice,
                dstPrice
            );
        }

        (convertedPrice, ) = _adjustDecimals(convertedPrice, 18, _dstDecimals);
        timestamp = srcTime < dstTime ? srcTime : dstTime;

        return (convertedPrice, timestamp);
    }

    /**
     * @notice Adjust decimals from one precision to another
     * @param _price Price to adjust
     * @param _srcDecimals Source decimals
     * @param _dstDecimals Destination decimals
     * @return adjustedPrice Price adjusted to destination decimals
     * @return timestamp Current timestamp
     */
    function _adjustDecimals(
        uint256 _price,
        uint8 _srcDecimals,
        uint8 _dstDecimals
    ) internal view returns (uint256 adjustedPrice, uint64 timestamp) {
        if (_srcDecimals == _dstDecimals) {
            return (_price, uint64(block.timestamp));
        }

        if (_srcDecimals > _dstDecimals) {
            adjustedPrice = _price / 10 ** (_srcDecimals - _dstDecimals);
        } else {
            adjustedPrice = _price * 10 ** (_dstDecimals - _srcDecimals);
        }
        timestamp = uint64(block.timestamp);
    }

    function getLocalAsset(
        uint32 _srcChainId,
        address _srcAsset
    ) public view returns (address localAsset, uint8 localDecimals) {
        bytes32 key = keccak256(abi.encodePacked(_srcChainId, _srcAsset));

        localAsset = crossChainAssetMap[key];

        // Only get decimals if localAsset is not zero address
        if (localAsset == address(0)) revert AssetNotConfigured(_srcAsset);

        localDecimals = _getAssetDecimals(localAsset);

        return (localAsset, localDecimals);
    }

    /**
     * @notice Internal function to check sequencer status
     * @dev Checks if sequencer is up and grace period has passed
     * @return isValid True if sequencer is up and grace period has passed, or if no sequencer check is needed (e.g. on L1)
     */
    function _isSequencerValid() internal view returns (bool isValid) {
        if (sequencer == address(0)) {
            return true; // No sequencer check needed (e.g. on L1)
        }

        (, int256 answer, uint256 startedAt, , ) = IChainlink(sequencer)
            .latestRoundData();

        // Answer == 0: Sequencer is up
        // Check that the sequencer is up or the grace period has passed
        if (answer != 0 || block.timestamp < startedAt + GRACE_PERIOD_TIME) {
            revert SequencerUnavailable();
        }

        return true;
    }

    /**
     * @notice Checks if a timestamp is considered stale
     * @dev Compares against PRICE_STALENESS_THRESHOLD
     * @param timestamp The timestamp to check
     * @return True if the timestamp is stale
     */
    function _isStale(uint256 timestamp) internal view returns (bool) {
        return block.timestamp - timestamp > PRICE_STALENESS_THRESHOLD;
    }

    /**
     * @notice Gets decimals for an asset
     * @dev Queries the token contract directly
     * @param asset The asset address
     * @return decimals The number of decimals
     */
    function _getAssetDecimals(address asset) internal view returns (uint8) {
        return IERC20Metadata(asset).decimals();
    }
}
