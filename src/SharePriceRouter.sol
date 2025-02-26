// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {ISharePriceRouter, PriceReturnData, VaultReport} from "./interfaces/ISharePriceRouter.sol";
import {BaseOracleAdapter} from "./libs/base/BaseOracleAdapter.sol";
import {IChainlink} from "./interfaces/chainlink/IChainlink.sol";

/**
 * @title SharePriceRouter
 * @notice A multi-adapter oracle system that supports multiple price feeds and fallback mechanisms
 * @dev This contract manages multiple oracle adapters and provides unified price conversion
 */
contract SharePriceRouter is OwnableRoles {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error InvalidRole();
    error InvalidChainId(uint32 receivedChainId);
    error AdapterNotFound();
    error AdapterAlreadyExists();
    error NoValidPrice();
    error InvalidPrice();
    error InvalidHeartbeat();
    error NoAdaptersConfigured();
    error InvalidPriceData();
    error ExceedsMaxReports();
    error InvalidAssetType();
    error SequencerDown();

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event AdapterAdded(address indexed adapter, uint256 indexed priority);
    event AdapterRemoved(address indexed adapter);
    event PriceStored(address indexed asset, uint256 price, uint256 timestamp);
    event RoleGranted(address indexed account, uint256 indexed role);
    event RoleRevoked(address indexed account, uint256 indexed role);
    event SharePriceUpdated(
        uint32 indexed chainId,
        address indexed vault,
        uint256 sharePrice,
        address rewardsDelegate
    );
    event SequencerUpdated(address oldSequencer, address newSequencer);
    event FallbackPriceUsed(
        address indexed vaultAddress,
        address indexed asset,
        uint256 sharePrice,
        string reason
    );
    event CrossChainAssetMapped(
        uint32 indexed srcChain,
        address indexed srcAsset,
        address indexed localAsset
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
    uint256 public constant MAX_REPORTS = 100;
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

    /// @notice ETH/USD price feed address (Chainlink)
    /// @dev Immutable value set in constructor
    address public immutable ETH_USD_FEED;

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

    /// @notice Mapping of cross-chain assets to their local equivalents
    /// @dev key = keccak256(srcChain, srcAsset)
    mapping(bytes32 => address) public crossChainAssetMap;

    /// @notice Asset categories for optimized conversion
    enum AssetCategory {
        UNKNOWN,
        BTC_LIKE, // WBTC, BTCb, TBTC, etc.
        ETH_LIKE, // ETH, stETH, rsETH, etc.
        STABLE // USDC, USDT, DAI, etc.
    }

    /// @notice Mapping of assets to their category
    mapping(address => AssetCategory) public assetCategories;

    /// @notice Mapping of oracle adapters to their priorities
    /// @dev Lower number means higher priority
    mapping(address => uint256) public adapterPriorities;

    /// @notice Array of all oracle adapters
    address[] public oracleAdapters;

    /// @notice Mapping of adapter address to its index in oracleAdapters array plus 1 (0 means not in array)
    mapping(address => uint256) private adapterIndices;

    /// @notice Mapping of asset to its last stored price data
    /// @dev asset => (price, timestamp)
    mapping(address => StoredPrice) public storedPrices;

    /// @notice Mapping from price key to struct vault report
    /// @dev Key is keccak256(abi.encodePacked(srcChainId, vaultAddress))
    mapping(bytes32 => VaultReport) public sharePrices;

    /// @notice Mapping of vault address to its chain ID
    mapping(address => uint32) public vaultChainIds;

    /// @notice Mapping of vault address to its last stored share price data
    /// @dev Packed into 2 storage slots:
    ///      Slot 1: sharePrice (248 bits) + decimals (8 bits)
    ///      Slot 2: asset (160 bits) + timestamp (64 bits)
    mapping(address => StoredSharePrice) public storedSharePrices;

    /// @notice Struct to store historical price data
    /// @dev Packed into a single storage slot:
    ///      price (240 bits) + timestamp (64 bits) + isUSD (1 bit)
    struct StoredPrice {
        uint240 price; // Reduced from uint256 since prices must fit uint240
        uint64 timestamp; // Packed with price
        bool isUSD; // Packed with price and timestamp
    }

    /// @notice Struct to store historical share price data
    /// @dev Packed into 2 storage slots:
    ///      Slot 1: sharePrice (248 bits) + decimals (8 bits)
    ///      Slot 2: asset (160 bits) + timestamp (64 bits)
    struct StoredSharePrice {
        uint248 sharePrice; // Reduced from uint256 since prices must fit uint240
        uint8 decimals; // Packed with sharePrice
        address asset; // New slot
        uint64 timestamp; // Packed with asset
    }

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
    constructor(
        address _admin,
        address _ethUsdFeed,
        address _usdc,
        address _wbtc,
        address _weth
    ) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_ethUsdFeed == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_wbtc == address(0)) revert ZeroAddress();
        if (_weth == address(0)) revert ZeroAddress();

        chainId = uint32(block.chainid);
        ETH_USD_FEED = _ethUsdFeed;
        USDC = _usdc;
        WBTC = _wbtc;
        WETH = _weth;

        // Set up base asset categories
        assetCategories[_usdc] = AssetCategory.STABLE;
        assetCategories[_wbtc] = AssetCategory.BTC_LIKE;
        assetCategories[_weth] = AssetCategory.ETH_LIKE;

        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                           ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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
     * @notice Adds a new oracle adapter
     * @dev Only callable by admin. Sets adapter priority and enables it
     * @param adapter Address of the oracle adapter to add
     * @param priority Priority level for the adapter (lower = higher priority)
     */
    function addAdapter(address adapter, uint256 priority) external onlyAdmin {
        if (adapter == address(0)) revert ZeroAddress();
        if (adapterPriorities[adapter] != 0) revert AdapterAlreadyExists();

        adapterPriorities[adapter] = priority;
        oracleAdapters.push(adapter);
        adapterIndices[adapter] = oracleAdapters.length;
        emit AdapterAdded(adapter, priority);
    }

    /**
     * @notice Internal function to remove an adapter from the system
     * @dev Handles removal of adapter while maintaining array consistency
     *      Uses a swap-and-pop pattern to avoid array shifting
     * @param adapter Address of the adapter to remove
     * @custom:throws AdapterNotFound if adapter is not in the system or already removed
     */
    function _removeAdapter(address adapter) internal {
        if (adapterPriorities[adapter] == 0) revert AdapterNotFound();

        uint256 index = adapterIndices[adapter];
        if (index == 0) revert AdapterNotFound();
        index--; // Convert from 1-based to 0-based index

        // Get the last adapter
        address lastAdapter = oracleAdapters[oracleAdapters.length - 1];

        // If not removing the last element, move the last element to the removed position
        if (index != oracleAdapters.length - 1) {
            oracleAdapters[index] = lastAdapter;
            adapterIndices[lastAdapter] = index + 1; // Update the moved adapter's index (1-based)
        }

        // Remove the last element
        oracleAdapters.pop();

        // Clean up storage
        delete adapterPriorities[adapter];
        delete adapterIndices[adapter];

        emit AdapterRemoved(adapter);
    }

    /**
     * @notice Removes an oracle adapter
     * @dev Only callable by admin. Completely removes adapter from the system
     * @param adapter Address of the oracle adapter to remove
     */
    function removeAdapter(address adapter) external onlyAdmin {
        _removeAdapter(adapter);
    }

    /**
     * @notice Sets the category for an asset
     * @dev Only callable by admin. Categories determine price conversion logic
     * @param asset The asset address
     * @param category The asset category (BTC_LIKE, ETH_LIKE, STABLE)
     */
    function setAssetCategory(
        address asset,
        AssetCategory category
    ) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddress();
        if (category == AssetCategory.UNKNOWN) revert InvalidAssetType();
        assetCategories[asset] = category;
    }

    /**
     * @notice Sets the sequencer uptime feed address
     * @dev Only callable by admin
     * @param _sequencer The new sequencer uptime feed address
     */
    function setSequencer(address _sequencer) external onlyAdmin {
        address oldSequencer = sequencer;
        sequencer = _sequencer;
        emit SequencerUpdated(oldSequencer, _sequencer);
    }

    /**
     * @notice Sets the mapping between a cross-chain asset and its local equivalent
     * @dev Only callable by admin. Maps assets from other chains to their Base equivalents
     * @param _srcChain The source chain ID
     * @param _srcAsset The asset address on the source chain
     * @param _localAsset The equivalent asset address on Base
     */
    function setCrossChainAssetMapping(
        uint32 _srcChain,
        address _srcAsset,
        address _localAsset
    ) external onlyAdmin {
        if (_srcChain == chainId) revert InvalidChainId(_srcChain);
        if (_srcAsset == address(0) || _localAsset == address(0))
            revert ZeroAddress();

        bytes32 key = keccak256(abi.encodePacked(_srcChain, _srcAsset));
        crossChainAssetMap[key] = _localAsset;

        emit CrossChainAssetMapped(_srcChain, _srcAsset, _localAsset);
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
     * @notice Checks if an asset is supported by any adapter
     * @dev Iterates through all adapters to check support
     * @param asset The asset to check
     * @return True if the asset is supported by any adapter
     */
    function isSupportedAsset(address asset) external view returns (bool) {
        for (uint256 i = 0; i < oracleAdapters.length; i++) {
            BaseOracleAdapter adapter = BaseOracleAdapter(oracleAdapters[i]);
            if (adapter.isSupportedAsset(asset)) {
                return true;
            }
        }
        return false;
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
     * @notice Gets the price for an asset from the best available adapter
     * @dev Returns price and error code (0 = no error)
     * @param asset The asset to get the price for
     * @param inUSD Whether to get the price in USD
     * @return price The price of the asset
     * @return errorCode Error code (0 = no error)
     */
    function getPrice(
        address asset,
        bool inUSD
    ) external view returns (uint256 price, uint256 errorCode) {
        try this.getLatestPrice(asset, inUSD) returns (
            uint256 p,
            uint256 timestamp,
            bool isUSD
        ) {
            if (p > 0 && !_isStale(timestamp) && isUSD == inUSD) {
                return (p, 0);
            }
        } catch {}
        return (0, 1);
    }

    /**
     * @notice Gets the latest price for an asset using all available adapters
     * @dev Tries adapters in priority order until valid price is found
     * @param asset Address of the asset
     * @param inUSD Whether to return the price in USD
     * @return price Latest price of the asset
     * @return timestamp Timestamp of the price
     * @return isUSD Whether the returned price is in USD
     */
    function getLatestPrice(
        address asset,
        bool inUSD
    ) public view returns (uint256 price, uint256 timestamp, bool isUSD) {
        if (oracleAdapters.length == 0) revert NoAdaptersConfigured();

        // Try all adapters in priority order
        for (uint256 i = 0; i < oracleAdapters.length; i++) {
            BaseOracleAdapter adapter = BaseOracleAdapter(oracleAdapters[i]);

            if (adapter.isSupportedAsset(asset)) {
                PriceReturnData memory priceData = adapter.getPrice(
                    asset,
                    inUSD
                );

                if (!priceData.hadError && priceData.price > 0) {
                    return (priceData.price, block.timestamp, priceData.inUSD);
                }
            }
        }

        // If no current price, check stored price
        StoredPrice memory storedPrice = storedPrices[asset];
        if (
            storedPrice.price > 0 &&
            block.timestamp - storedPrice.timestamp <= PRICE_STALENESS_THRESHOLD
        ) {
            return (
                storedPrice.price,
                storedPrice.timestamp,
                storedPrice.isUSD
            );
        }

        revert NoValidPrice(); // TODO SHOULD NEVER REVERT
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
     *      1. Current price calculation (through oracles)
     *      2. Cross-chain price for remote vaults using stored VaultReport
     *      3. Destination vault's own share price as final fallback
     * @param _srcChain Chain ID where the vault exists
     * @param _vaultAddress Address of the vault
     * @param _dstAsset Address of the destination asset (local chain)
     * @return sharePrice Current share price in terms of _dstAsset
     * @return timestamp Timestamp of the price data
     */
    function getLatestSharePrice(
        uint32 _srcChain,
        address _vaultAddress,
        address _dstAsset
    ) external view returns (uint256 sharePrice, uint64 timestamp) {
        if (_vaultAddress == address(0) || _dstAsset == address(0)) {
            return _getFallbackSharePrice(_dstAsset);
        }

        if (_srcChain != chainId) {
            VaultReport memory report = sharePrices[
                getPriceKey(_srcChain, _vaultAddress)
            ];
            if (report.sharePrice > 0) {
                // Get cross-chain price conversion
                (uint256 assetPrice, uint64 priceTimestamp) = _getCrossChainAssetPrice(
                    report.asset,
                    _srcChain,
                    _dstAsset,
                    true // Use USD as intermediate
                );

                if (assetPrice > 0) {
                    sharePrice = FixedPointMathLib.mulDiv(
                        report.sharePrice,
                        assetPrice,
                        10 ** uint8(report.assetDecimals)
                    );
                    return (sharePrice, priceTimestamp);
                }
            }

            // If current price not available, try stored price from updateSharePrices
            StoredSharePrice memory stored = storedSharePrices[_vaultAddress];
            if (stored.sharePrice > 0 && !_isStale(stored.timestamp)) {
                if (stored.asset == _dstAsset) {
                    return (stored.sharePrice, stored.timestamp);
                }

                // Try to convert stored price to destination asset
                try
                    this.convertStoredPrice(
                        stored.sharePrice,
                        stored.asset,
                        _dstAsset
                    )
                returns (uint256 convertedPrice, uint64 convertedTime) {
                    if (convertedPrice > 0) {
                        return (convertedPrice, convertedTime);
                    }
                } catch {}
            }
        } else {
            // For local vaults, try current calculation first
            try this.calculateSharePrice(_vaultAddress, _dstAsset) returns (
                uint256 currentPrice,
                uint64 currentTime
            ) {
                if (currentPrice > 0) {
                    return (currentPrice, currentTime);
                }
            } catch {}
        }

        
        _getFallbackSharePrice(_dstAsset);
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
     * @notice Calculates current share price without storing it
     * @dev This is separated to allow for view-only calls and cleaner error handling
     * @param _vaultAddress The address of the vault to calculate price for
     * @param _dstAsset The asset to denominate the share price in
     * @return sharePrice The calculated share price in terms of _dstAsset
     * @return timestamp The timestamp of the calculation
     */
    function calculateSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) external view returns (uint256 sharePrice, uint64 timestamp) {
        return _getDstSharePrice(_vaultAddress, _dstAsset);
    }

    /**
     * @notice Updates and stores the latest price for an asset
     * @dev Fetches the latest price and stores it in the contract state
     * @param asset Address of the asset to update
     * @param inUSD Whether to store the price in USD (true) or ETH (false)
     */
    function updatePrice(address asset, bool inUSD) external {
        (uint256 price, uint256 timestamp, bool isUSD) = getLatestPrice(
            asset,
            inUSD
        );

        storedPrices[asset] = StoredPrice({
            price: uint240(price), // Explicit cast to uint240
            timestamp: uint64(timestamp), // Explicit cast to uint64
            isUSD: isUSD
        });

        emit PriceStored(asset, price, timestamp);
    }

    /**
     * @notice Updates share prices from another chain via LayerZero
     * @dev Only callable by endpoint. Validates chain IDs and report count
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(
        uint32 _srcChainId,
        VaultReport[] calldata reports
    ) external onlyEndpoint {
        if (reports.length == 0) return;
        if (_srcChainId == chainId) revert InvalidChainId(_srcChainId);
        if (reports.length > MAX_REPORTS) revert ExceedsMaxReports();

        bytes32 key;
        for (uint256 i = 0; i < reports.length; i++) {
            VaultReport calldata report = reports[i];
            if (report.chainId != _srcChainId) {
                revert InvalidChainId(report.chainId);
            }
            if (report.sharePrice == 0) revert InvalidPrice();

            // Track the chain ID for this vault
            vaultChainIds[report.vaultAddress] = _srcChainId;

            key = getPriceKey(_srcChainId, report.vaultAddress);
            sharePrices[key] = report;

            // Try to get a local equivalent price and store it
            bytes32 assetKey = keccak256(
                abi.encodePacked(_srcChainId, report.asset)
            );
            address localEquivalent = crossChainAssetMap[assetKey];

            if (localEquivalent != address(0)) {
                // Store the share price in terms of the local equivalent (e.g. DAI)
                // First adjust decimals from source asset to local equivalent
                (uint256 adjustedPrice, uint64 adjustedTime) = _adjustDecimals(
                    report.sharePrice,
                    uint8(report.assetDecimals),
                    _getAssetDecimals(localEquivalent)
                );

                if (adjustedPrice > 0) {
                    storedSharePrices[report.vaultAddress] = StoredSharePrice({
                        sharePrice: uint248(adjustedPrice),
                        decimals: _getAssetDecimals(localEquivalent),
                        asset: localEquivalent, // Store in terms of local equivalent
                        timestamp: adjustedTime
                    });
                }
            } else {
                // If no local equivalent, try USD conversion
                try this.getLatestPrice(report.asset, true) returns (
                    uint256 srcUsdPrice,
                    uint256 srcTimestamp,
                    bool isUSD
                ) {
                    if (srcUsdPrice > 0 && isUSD) {
                        storedSharePrices[
                            report.vaultAddress
                        ] = StoredSharePrice({
                            sharePrice: uint248(report.sharePrice),
                            decimals: uint8(report.assetDecimals),
                            asset: report.asset,
                            timestamp: uint64(srcTimestamp)
                        });
                    }
                } catch {}
            }

            emit SharePriceUpdated(
                _srcChainId,
                report.vaultAddress,
                report.sharePrice,
                report.rewardsDelegate
            );
        }
    }

    /**
     * @notice Converts a stored price to a different denomination
     * @dev All adapters return standardized prices, so we can use the same conversion for all
     */
    function convertStoredPrice(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) external view returns (uint256 price, uint64 timestamp) {
        // If same asset, just adjust decimals if needed
        if (_storedAsset == _dstAsset) {
            return _getAndAdjustDecimals(_storedAsset, _storedPrice, _dstAsset);
        }

        // Get asset categories
        AssetCategory srcCategory = assetCategories[_storedAsset];
        AssetCategory dstCategory = assetCategories[_dstAsset];

        // Require both assets to be categorized
        if (
            srcCategory == AssetCategory.UNKNOWN ||
            dstCategory == AssetCategory.UNKNOWN
        ) {
            revert InvalidAssetType();
        }

        // Handle same category conversions
        if (srcCategory == dstCategory) {
            if (
                srcCategory == AssetCategory.ETH_LIKE ||
                srcCategory == AssetCategory.BTC_LIKE
            ) {
                return
                    _convertSameCategory(
                        _storedPrice,
                        _storedAsset,
                        _dstAsset,
                        false
                    );
            } else if (srcCategory == AssetCategory.STABLE) {
                return
                    _convertSameCategory(
                        _storedPrice,
                        _storedAsset,
                        _dstAsset,
                        true
                    );
            }
        }

        // Handle cross-category conversions through USD
        return _convertCrossCategory(_storedPrice, _storedAsset, _dstAsset);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////* /
    
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
            return false;
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

    /**
     * @notice Gets decimals for a potentially cross-chain asset
     * @dev Handles both local and cross-chain assets:
     *      - For local assets: Queries the token contract directly
     *      - For cross-chain assets: Retrieves from stored VaultReport
     * @param asset The asset address
     * @param chainId_ The chain ID where the asset exists
     * @return decimals The number of decimals
     * @custom:edge-case Returns 0 if cross-chain report doesn't exist
     */
    function _getAssetDecimalsWithReport(
        address asset,
        uint32 chainId_
    ) internal view returns (uint8) {
        if (chainId_ != 0 && chainId_ != chainId) {
            // Use stored decimals from VaultReport for cross-chain assets
            VaultReport memory report = sharePrices[
                getPriceKey(chainId_, asset)
            ];
            return uint8(report.assetDecimals);
        }
        return _getAssetDecimals(asset);
    }

    /**
     * @notice Helper function to get and adjust decimals for asset conversion
     * @dev Handles both cross-chain and local assets
     * @param _asset The asset to get decimals for
     * @param _price The price to adjust
     * @param _dstAsset The destination asset
     * @return adjustedPrice The price adjusted for decimals
     * @return timestamp The timestamp of the adjustment
     */
    function _getAndAdjustDecimals(
        address _asset,
        uint256 _price,
        address _dstAsset
    ) internal view returns (uint256 adjustedPrice, uint64 timestamp) {
        uint32 srcChain = vaultChainIds[_asset];
        uint32 dstChain = vaultChainIds[_dstAsset];

        uint8 srcDecimals = _getAssetDecimalsWithReport(_asset, srcChain);
        uint8 dstDecimals = _getAssetDecimalsWithReport(_dstAsset, dstChain);

        return _adjustDecimals(_price, srcDecimals, dstDecimals);
    }

    /**
     * @notice Adjusts token amounts for decimal differences
     * @dev Handles scaling of amounts when source and destination decimals differ:
     *      - If srcDecimals > dstDecimals: Scales down by dividing
     *      - If srcDecimals < dstDecimals: Scales up by multiplying
     *      - If decimals match: Returns original amount
     * @param amount The amount to adjust
     * @param srcDecimals Source token decimals
     * @param dstDecimals Destination token decimals
     * @return adjustedAmount The decimal-adjusted amount
     * @return timestamp Current block timestamp
     * @custom:edge-case May return 0 if scaling down results in complete loss of precision
     */
    function _adjustDecimals(
        uint256 amount,
        uint8 srcDecimals,
        uint8 dstDecimals
    ) internal view returns (uint256 adjustedAmount, uint64 timestamp) {
        if (srcDecimals == dstDecimals) {
            return (amount, uint64(block.timestamp));
        }

        if (srcDecimals > dstDecimals) {
            uint256 divisor = 10 ** (srcDecimals - dstDecimals);
            adjustedAmount = FixedPointMathLib.mulDiv(amount, 1, divisor);
        } else {
            uint256 multiplier = 10 ** (dstDecimals - srcDecimals);
            adjustedAmount = FixedPointMathLib.mulDiv(amount, multiplier, 1);
        }

        return (adjustedAmount, uint64(block.timestamp));
    }

    /**
     * @notice Provides a fallback price for invalid inputs
     * @dev Used when input parameters are invalid (zero addresses)
     * @param _dstAsset The destination asset (may be zero)
     * @return price A fallback price (may be zero)
     * @return timestamp The current timestamp
     */
    function _getFallbackSharePrice(
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // For safety with invalid inputs, we'll return 0 rather than a potentially disruptive value
        // This is safer as consuming contracts should already handle zero price cases

        // Only if the destination asset is a valid ERC4626 vault, try to get its share price
        if (_dstAsset != address(0)) {
            try IERC20Metadata(_dstAsset).decimals() returns (
                uint8 dstDecimals
            ) {
                try
                    IERC4626(msg.sender).convertToAssets(10 ** dstDecimals)
                returns (uint256 fallbackPrice) {
                    return (fallbackPrice, uint64(block.timestamp));
                } catch {}
            } catch {}
        }

        return (0, uint64(block.timestamp));
    }

    /**
     * @notice Validates a price and its timestamp
     * @dev Performs multiple validation checks:
     *      1. Price is above minimum threshold (MIN_PRICE_THRESHOLD)
     *      2. Price is not stale (within PRICE_STALENESS_THRESHOLD)
     *      3. Price fits within uint240 storage
     * @param price The price to validate
     * @param timestamp The timestamp of the price
     * @return valid Whether the price is valid
     * @custom:edge-case Returns false for prices that would overflow uint240 storage
     */
    function _validatePrice(
        uint256 price,
        uint256 timestamp
    ) internal view returns (bool valid) {
        // Remove minimum threshold check since we want to allow any non-zero price
        if (price == 0) return false;
        if (block.timestamp - timestamp > PRICE_STALENESS_THRESHOLD)
            return false;
        if (price > type(uint240).max) return false;
        return true;
    }

    /**
     * @notice Stores a share price with metadata
     * @dev Updates storedSharePrices mapping with:
     *      1. Share price (truncated to uint248)
     *      2. Asset decimals from the vault's asset
     *      3. Asset address
     *      4. Current timestamp
     * @param _vaultAddress The vault address
     * @param _price The share price to store
     * @param _timestamp The timestamp of the price
     * @custom:edge-case Silently truncates prices larger than uint248
     */
    function _storeSharePrice(
        address _vaultAddress,
        uint256 _price,
        uint64 _timestamp
    ) internal {
        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();

        storedSharePrices[_vaultAddress] = StoredSharePrice({
            sharePrice: uint248(_price),
            decimals: uint8(_getAssetDecimals(asset)),
            asset: asset,
            timestamp: _timestamp
        });
    }

    /**
     * @notice Gets the cross-chain price for a vault
     * @dev Attempts to retrieve and convert a price from another chain:
     *      1. Checks for direct price match (same asset)
     *      2. Attempts price conversion if assets differ
     *      3. Validates converted price before returning
     * @param _vaultAddress The vault address
     * @param _dstAsset The destination asset
     * @param _srcChain The source chain ID
     * @return price The converted price in terms of _dstAsset
     * @return timestamp The price timestamp as uint64
     * @custom:edge-case Returns (0,0) if:
     *      - No valid price exists
     *      - Price conversion fails
     *      - Converted price fails validation
     */
    function _getCrossChainPrice(
        address _vaultAddress,
        address _dstAsset,
        uint32 _srcChain
    ) internal view returns (uint256 price, uint64 timestamp) {
        bytes32 key = getPriceKey(_srcChain, _vaultAddress);
        VaultReport memory report = sharePrices[key];

        if (report.sharePrice > 0) {
            if (report.asset == _dstAsset) {
                return (report.sharePrice, uint64(report.lastUpdate));
            }

            try
                this.convertStoredPrice(
                    report.sharePrice,
                    report.asset,
                    _dstAsset
                )
            returns (uint256 convertedPrice, uint64 convertedTime) {
                if (_validatePrice(convertedPrice, convertedTime)) {
                    return (convertedPrice, convertedTime);
                }
            } catch {}
        }
        return (0, 0);
    }

    /**
     * @notice Gets share price for a vault with standardized conversion
     * @dev Process:
     *      1. Gets raw share price from vault in terms of its asset
     *      2. If destination asset differs, converts price
     *      3. Handles decimal adjustments during conversion
     * @param _vaultAddress The address of the vault
     * @param _dstAsset The destination asset to convert the price to
     * @return price The share price in terms of _dstAsset
     * @return timestamp The timestamp of the price
     */
    function _getDstSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();

        uint8 assetDecimals = _getAssetDecimals(asset);
        uint256 assetUnit = 10 ** assetDecimals;

        try vault.convertToAssets(assetUnit) returns (uint256 rawSharePrice) {
            if (rawSharePrice > 0) {
                if (asset == _dstAsset) {
                    return (rawSharePrice, uint64(block.timestamp));
                }

                try
                    this.convertStoredPrice(rawSharePrice, asset, _dstAsset)
                returns (uint256 convertedPrice, uint64 convertedTime) {
                    if (convertedPrice > 0) {
                        return (convertedPrice, convertedTime);
                    }
                } catch {}
            }
        } catch {}

        // Return 0 to allow fallback in getLatestSharePrice
        return (0, 0);
    }

    /**
     * @notice Gets the price for a cross-chain asset
     * @dev Uses local equivalent mapping and price feeds to convert cross-chain prices
     * @param _srcAsset The source chain asset address
     * @param _srcChain The source chain ID
     * @param _dstAsset The destination asset to price against
     * @param _inUSD Whether to use USD as intermediate
     * @return price The converted price
     * @return timestamp The timestamp of the price
     */
    function _getCrossChainAssetPrice(
        address _srcAsset,
        uint32 _srcChain,
        address _dstAsset,
        bool _inUSD
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Part 1: Handle local equivalent pathway
        {
            // Get local equivalent mapping
            bytes32 mappingKey = keccak256(
                abi.encodePacked(_srcChain, _srcAsset)
            );
            address localEquivalent = crossChainAssetMap[mappingKey];

            if (localEquivalent != address(0)) {
                // If we have a local equivalent mapped, use it

                // Get source report for decimals and share price
                bytes32 reportKey = getPriceKey(_srcChain, _srcAsset);
                VaultReport memory report = sharePrices[reportKey];
                uint8 srcDecimals = uint8(report.assetDecimals);

                // If local equivalent is the destination asset, direct conversion with decimal adjustment
                if (localEquivalent == _dstAsset) {
                    return
                        _adjustDecimals(
                            report.sharePrice,
                            srcDecimals,
                            _getAssetDecimals(_dstAsset)
                        );
                }

                // Try USD conversion pathway using local equivalent
                return
                    _tryLocalEquivalentUsdConversion(
                        report.sharePrice,
                        srcDecimals,
                        localEquivalent,
                        _dstAsset,
                        _getAssetDecimals(_dstAsset)
                    );
            }
        }

        // Part 2: Direct USD conversion pathway (when no local equivalent or it failed)
        return _tryDirectUsdConversion(_srcAsset, _srcChain, _dstAsset);
    }

    /**
     * @notice Helper function to try USD conversion through local equivalent
     * @dev Separated to manage stack depth
     */
    function _tryLocalEquivalentUsdConversion(
        uint256 sharePrice,
        uint8 srcDecimals,
        address localEquivalent,
        address dstAsset,
        uint8 dstDecimals
    ) internal view returns (uint256 price, uint64 timestamp) {
        uint256 localUsdPrice;
        uint256 localTimestamp;
        bool isUsdLocal;

        // Get local equivalent USD price
        try this.getLatestPrice(localEquivalent, true) returns (
            uint256 _localPrice,
            uint256 _localTime,
            bool _isUsdLocal
        ) {
            localUsdPrice = _localPrice;
            localTimestamp = _localTime;
            isUsdLocal = _isUsdLocal;

            // Early return if price is invalid
            if (localUsdPrice == 0 || !isUsdLocal) {
                return (0, 0);
            }
        } catch {
            return (0, 0);
        }

        // Get destination asset USD price
        uint256 dstUsdPrice;
        uint256 dstTimestamp;
        bool isUsdDst;

        try this.getLatestPrice(dstAsset, true) returns (
            uint256 _dstPrice,
            uint256 _dstTime,
            bool _isUsdDst
        ) {
            dstUsdPrice = _dstPrice;
            dstTimestamp = _dstTime;
            isUsdDst = _isUsdDst;

            // Early return if price is invalid
            if (dstUsdPrice == 0 || !isUsdDst) {
                return (0, 0);
            }
        } catch {
            return (0, 0);
        }

        // Convert using price ratio
        price = FixedPointMathLib.mulDiv(
            sharePrice,
            localUsdPrice,
            dstUsdPrice
        );

        // Adjust for decimal differences
        if (srcDecimals != dstDecimals) {
            if (srcDecimals > dstDecimals) {
                price = price / (10 ** (srcDecimals - dstDecimals));
            } else {
                price = price * (10 ** (dstDecimals - srcDecimals));
            }
        }

        // Use earliest timestamp
        timestamp = uint64(
            localTimestamp < dstTimestamp ? localTimestamp : dstTimestamp
        );

        return (price, timestamp);
    }

    /**
     * @notice Helper function to try direct USD conversion without local equivalent
     * @dev Separated to manage stack depth
     */
    function _tryDirectUsdConversion(
        address srcAsset,
        uint32 srcChain,
        address dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get source report for decimals and share price
        bytes32 reportKey = getPriceKey(srcChain, srcAsset);
        VaultReport memory report = sharePrices[reportKey];
        uint8 srcDecimals = uint8(report.assetDecimals);
        uint256 sharePrice = report.sharePrice;

        // Get source asset USD price
        uint256 srcUsdPrice;
        uint256 srcTimestamp;
        bool isUsdSrc;

        try this.getLatestPrice(srcAsset, true) returns (
            uint256 _srcPrice,
            uint256 _srcTime,
            bool _isUsdSrc
        ) {
            srcUsdPrice = _srcPrice;
            srcTimestamp = _srcTime;
            isUsdSrc = _isUsdSrc;

            // Early return if price is invalid
            if (srcUsdPrice == 0 || !isUsdSrc) {
                return (0, 0);
            }
        } catch {
            return (0, 0);
        }

        // Get destination asset USD price
        uint256 dstUsdPrice;
        uint256 dstTimestamp;
        bool isUsdDst;
        uint8 dstDecimals = _getAssetDecimals(dstAsset);

        try this.getLatestPrice(dstAsset, true) returns (
            uint256 _dstPrice,
            uint256 _dstTime,
            bool _isUsdDst
        ) {
            dstUsdPrice = _dstPrice;
            dstTimestamp = _dstTime;
            isUsdDst = _isUsdDst;

            // Early return if price is invalid
            if (dstUsdPrice == 0 || !isUsdDst) {
                return (0, 0);
            }
        } catch {
            return (0, 0);
        }

        // Convert using price ratio
        price = FixedPointMathLib.mulDiv(sharePrice, srcUsdPrice, dstUsdPrice);

        // Adjust for decimal differences
        if (srcDecimals != dstDecimals) {
            if (srcDecimals > dstDecimals) {
                price = price / (10 ** (srcDecimals - dstDecimals));
            } else {
                price = price * (10 ** (dstDecimals - srcDecimals));
            }
        }

        // Use earliest timestamp
        timestamp = uint64(
            srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp
        );

        return (price, timestamp);
    }

    /**
     * @notice Converts a price within the same asset category
     * @dev Conversion process:
     *      1. Gets current prices for both assets in same denomination
     *      2. Calculates conversion ratio while maintaining precision
     *      3. Adjusts decimals if needed
     * @param _storedPrice Original price to convert
     * @param _storedAsset Source asset address
     * @param _dstAsset Destination asset address
     * @param _inUSD Whether to use USD prices for conversion
     * @return price Converted price in destination asset terms
     * @return timestamp Timestamp of the conversion
     * @custom:throws NoValidPrice if either asset price is unavailable
     */
    function _convertSameCategory(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset,
        bool _inUSD
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get prices in appropriate denomination (USD or ETH/BTC)
        (uint256 srcPrice, uint256 srcTimestamp, ) = getLatestPrice(
            _storedAsset,
            _inUSD
        );
        (uint256 dstPrice, uint256 dstTimestamp, ) = getLatestPrice(
            _dstAsset,
            _inUSD
        );

        if (srcPrice == 0 || dstPrice == 0) revert NoValidPrice();

        // Convert using ratio of prices
        price = FixedPointMathLib.mulDiv(_storedPrice, srcPrice, dstPrice);

        // Use earliest timestamp
        timestamp = uint64(
            srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp
        );

        // Handle decimal adjustments if needed
        return _getAndAdjustDecimals(_storedAsset, price, _dstAsset);
    }

    /**
     * @notice Converts a price between different asset categories
     * @dev Conversion process:
     *      1. Gets USD prices for both assets
     *      2. Converts through USD as intermediate step
     *      3. Handles decimal scaling during conversion
     * @param _storedPrice Original price to convert
     * @param _storedAsset Source asset address
     * @param _dstAsset Destination asset address
     * @return price Converted price in destination asset terms
     * @return timestamp Timestamp of the conversion
     * @custom:throws NoValidPrice if either USD price is unavailable
     * @custom:edge-case May lose precision during decimal adjustments
     */
    function _convertCrossCategory(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get USD prices for both assets
        (uint256 srcUsdPrice, uint256 srcTimestamp, ) = getLatestPrice(
            _storedAsset,
            true
        );
        (uint256 dstUsdPrice, uint256 dstTimestamp, ) = getLatestPrice(
            _dstAsset,
            true
        );

        if (srcUsdPrice == 0 || dstUsdPrice == 0) revert NoValidPrice();

        // Get decimals
        uint32 srcChain = vaultChainIds[_storedAsset];
        uint32 dstChain = vaultChainIds[_dstAsset];

        uint8 srcDecimals = _getAssetDecimalsWithReport(_storedAsset, srcChain);
        uint8 dstDecimals = _getAssetDecimalsWithReport(_dstAsset, dstChain);

        // First convert to USD equivalent value
        uint256 usdValue = _storedPrice * srcUsdPrice;

        // Then convert to destination asset with proper decimal scaling
        if (srcDecimals <= dstDecimals) {
            price = FixedPointMathLib.mulDiv(
                usdValue * (10 ** (dstDecimals - srcDecimals)),
                1,
                dstUsdPrice
            );
        } else {
            price = FixedPointMathLib.mulDiv(
                usdValue,
                1,
                dstUsdPrice * (10 ** (srcDecimals - dstDecimals))
            );
        }

        timestamp = uint64(
            srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp
        );
    }

    /**
     * @notice Removes a price feed for a specific asset triggered by an adapter's notification
     * @dev Requires that the feed exists for the asset
     */
    function notifyFeedRemoval(address) external {
        _removeAdapter(msg.sender);
    }
}
