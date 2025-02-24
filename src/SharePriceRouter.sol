// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "@solady/utils/FixedPointMathLib.sol";
import {IERC4626} from "./interfaces/IERC4626.sol";
import {IERC20Metadata} from "./interfaces/IERC20Metadata.sol";
import {IOracleAdaptor, PriceReturnData} from "./interfaces/IOracleAdaptor.sol";
import {VaultReport} from "./interfaces/ISharePriceRouter.sol";
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
    /// @notice Precision for price calculations (1e18)
    uint256 public constant PRECISION = 1e18;
    /// @notice Minimum valid price threshold
    uint256 public constant MIN_PRICE_THRESHOLD = 1e2; // 0.0000000001 in 18 decimals
    /// @notice Grace period after sequencer is back up
    uint256 public constant GRACE_PERIOD_TIME = 3600; // 1 hour

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Chain ID this oracle is deployed on
    uint32 public immutable chainId;

    /// @notice ETH/USD price feed address (Chainlink)
    address public immutable ETH_USD_FEED;

    /// @notice Common base assets
    address public immutable USDC;
    address public immutable WBTC;
    address public immutable WETH;

    /// @notice Sequencer uptime feed address
    address public sequencer;

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
    mapping(address => StoredSharePrice) public storedSharePrices;

    /// @notice Struct to store historical price data
    struct StoredPrice {
        uint256 price;
        uint256 timestamp;
        bool isUSD;
    }

    /// @notice Struct to store historical share price data
    struct StoredSharePrice {
        uint256 sharePrice;
        uint256 timestamp;
        address asset;
        uint8 decimals;
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
     * @param adapter Address of the adapter to remove
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
        if (adapter == address(0)) revert ZeroAddress();
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
            IOracleAdaptor adapter = IOracleAdaptor(oracleAdapters[i]);
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
     * @param getLower Whether to get the lower of two prices if available
     * @return price The price of the asset
     * @return errorCode Error code (0 = no error)
     */
    function getPrice(
        address asset,
        bool inUSD,
        bool getLower
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
            IOracleAdaptor adapter = IOracleAdaptor(oracleAdapters[i]);

            if (adapter.isSupportedAsset(asset)) {
                PriceReturnData memory priceData = adapter.getPrice(
                    asset,
                    inUSD,
                    true
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

            // Get latest price in USD
            (uint256 price, , ) = getLatestPrice(asset, true);

            reports[i] = VaultReport({
                chainId: chainId,
                vaultAddress: vaultAddress,
                asset: asset,
                assetDecimals: assetDecimals,
                sharePrice: price,
                lastUpdate: uint64(block.timestamp),
                rewardsDelegate: rewardsDelegate
            });
        }
    }

    /**
     * @notice Gets the latest share price for a vault
     * @dev Tries multiple methods to get the price in order:
     *      1. Current price calculation
     *      2. Cross-chain price for remote vaults
     *      3. Stored prices
     *      4. Raw vault ratio if assets match
     *      5. 1:1 ratio as absolute fallback
     * @param _vaultAddress Address of the vault
     * @param _dstAsset Asset to get the price in
     * @return sharePrice Current share price in terms of _dstAsset
     * @return timestamp Timestamp of the price data
     */
    function getLatestSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) external returns (uint256 sharePrice, uint64 timestamp) {
        // Always try to get current price first
        try this.calculateSharePrice(_vaultAddress, _dstAsset) returns (
            uint256 currentPrice,
            uint64 currentTime
        ) {
            if (currentPrice > 0 && _validatePrice(currentPrice, currentTime)) {
                _storeSharePrice(_vaultAddress, currentPrice, currentTime);
                return (currentPrice, currentTime);
            }
        } catch {}

        // Fallback to cross-chain price for remote vaults
        uint32 vaultChain = vaultChainIds[_vaultAddress];
        if (vaultChain != 0 && vaultChain != chainId) {
            (sharePrice, timestamp) = _getCrossChainPrice(
                _vaultAddress,
                _dstAsset,
                vaultChain
            );
            if (sharePrice > 0 && !_isStale(timestamp)) {
                return (sharePrice, uint64(timestamp));
            }
        }

        // Try stored prices as last resort
        StoredSharePrice memory stored = storedSharePrices[_vaultAddress];
        if (stored.sharePrice > 0) {
            if (stored.asset == _dstAsset && !_isStale(stored.timestamp)) {
                return (stored.sharePrice, uint64(stored.timestamp));
            }

            if (!_isStale(stored.timestamp)) {
                try
                    this.convertStoredPrice(
                        stored.sharePrice,
                        stored.asset,
                        _dstAsset
                    )
                returns (uint256 convertedPrice, uint64 convertedTime) {
                    bool validPrice = _validatePrice(
                        convertedPrice,
                        convertedTime
                    );
                    if (validPrice) {
                        return (convertedPrice, convertedTime);
                    }
                } catch (bytes memory /* err */) {
                    // Continue with next attempt if conversion fails
                }
            }

            // Use stale stored price rather than 1:1 if we have it
            if (stored.asset != _dstAsset) {
                try
                    this.convertStoredPrice(
                        stored.sharePrice,
                        stored.asset,
                        _dstAsset
                    )
                returns (uint256 convertedPrice, uint64 convertedTime) {
                    return (convertedPrice, convertedTime);
                } catch {}
            }
            return (stored.sharePrice, uint64(stored.timestamp));
        }

        // Final fallback: Use raw vault ratio if assets match
        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();

        if (asset == _dstAsset) {
            uint256 rawPrice = vault.convertToAssets(PRECISION);
            return (
                rawPrice > 0 ? rawPrice : PRECISION,
                uint64(block.timestamp)
            );
        }

        // Absolute last resort: Return 1:1 ratio
        return (PRECISION, uint64(block.timestamp));
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
            price: price,
            timestamp: timestamp,
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

            // Store the share price in the asset's native decimals
            storedSharePrices[report.vaultAddress] = StoredSharePrice({
                sharePrice: report.sharePrice,
                timestamp: block.timestamp,
                asset: report.asset,
                decimals: uint8(report.assetDecimals) // Explicit conversion to uint8
            });

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
            // Check if this is a cross-chain asset
            uint32 srcChain = vaultChainIds[_storedAsset];
            uint8 srcDecimals;
            if (srcChain != 0 && srcChain != chainId) {
                // Use stored decimals from VaultReport for cross-chain assets
                VaultReport memory report = sharePrices[getPriceKey(srcChain, _storedAsset)];
                srcDecimals = uint8(report.assetDecimals);
            } else {
                srcDecimals = _getAssetDecimals(_storedAsset);
            }
            uint8 dstDecimals = _getAssetDecimals(_dstAsset);
            (price, ) = _adjustDecimals(_storedPrice, srcDecimals, dstDecimals);
            return (price, uint64(block.timestamp));
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
            if (srcCategory == AssetCategory.ETH_LIKE || srcCategory == AssetCategory.BTC_LIKE) {
                return _convertSameCategory(_storedPrice, _storedAsset, _dstAsset, false);
            } else if (srcCategory == AssetCategory.STABLE) {
                return _convertSameCategory(_storedPrice, _storedAsset, _dstAsset, true);
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
     * @return True if sequencer is valid
     */
    function _isSequencerValid() internal view returns (bool) {
        if (sequencer == address(0)) {
            return true; // No sequencer check needed (e.g. on L1)
        }

        (, int256 answer, uint256 startedAt, , ) = IChainlink(sequencer).latestRoundData();

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
     * @dev Returns decimals from VaultReport if cross-chain, otherwise queries token
     * @param asset The asset address
     * @param chain The chain ID where the asset exists
     * @return decimals The number of decimals
     */
    function _getAssetDecimalsWithReport(
        address asset,
        uint32 chain
    ) internal view returns (uint8) {
        if (chain != 0 && chain != chainId) {
            // Use stored decimals from VaultReport for cross-chain assets
            VaultReport memory report = sharePrices[getPriceKey(chain, asset)];
            return uint8(report.assetDecimals);
        }
        return _getAssetDecimals(asset);
    }

    function _adjustDecimals(
        uint256 amount,
        uint8 srcDecimals,
        uint8 dstDecimals
    ) internal view returns (uint256 adjustedAmount, uint64 timestamp) {
        if (srcDecimals == dstDecimals) {
            return (amount, uint64(block.timestamp));
        }

        if (srcDecimals > dstDecimals) {
            // Scale down
            adjustedAmount = amount / (10 ** (srcDecimals - dstDecimals));
        } else {
            // Scale up
            adjustedAmount = amount * (10 ** (dstDecimals - srcDecimals));
        }

        return (adjustedAmount, uint64(block.timestamp));
    }

    /**
     * @notice Validates a price and its timestamp
     * @dev Checks if:
     *      1. Price is above minimum threshold
     *      2. Price is not stale
     *      3. Price fits within uint240
     * @param price The price to validate
     * @param timestamp The timestamp of the price
     * @return valid Whether the price is valid
     */
    function _validatePrice(
        uint256 price,
        uint256 timestamp
    ) internal view returns (bool valid) {
        if (price == 0 || price < MIN_PRICE_THRESHOLD) return false;
        if (block.timestamp - timestamp > PRICE_STALENESS_THRESHOLD)
            return false;
        if (price > type(uint240).max) return false;
        return true;
    }

    /**
     * @notice Stores a share price with metadata
     * @dev Updates the storedSharePrices mapping with current price data
     * @param _vaultAddress The vault address
     * @param _price The share price to store
     * @param _timestamp The timestamp of the price
     */
    function _storeSharePrice(
        address _vaultAddress,
        uint256 _price,
        uint64 _timestamp
    ) internal {
        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();

        storedSharePrices[_vaultAddress] = StoredSharePrice({
            sharePrice: _price,
            timestamp: _timestamp,
            asset: asset,
            decimals: _getAssetDecimals(asset)
        });
    }

    /**
     * @notice Gets the cross-chain price for a vault
     * @dev Attempts to get and convert a price from another chain
     *      Returns (0,0) if no valid price is found
     * @param _vaultAddress The vault address
     * @param _dstAsset The destination asset
     * @param _srcChain The source chain ID
     * @return price The converted price in terms of _dstAsset
     * @return timestamp The price timestamp as uint64
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
     * @dev First gets raw share price from vault, then converts to destination asset if needed
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

        uint256 rawSharePrice = vault.convertToAssets(assetUnit);

        if (asset == _dstAsset) {
            return (rawSharePrice, uint64(block.timestamp));
        }

        return this.convertStoredPrice(rawSharePrice, asset, _dstAsset);
    }

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
        price = FixedPointMathLib.mulDiv(
            _storedPrice,
            srcPrice,
            dstPrice
        );

        // Use earliest timestamp
        timestamp = uint64(
            srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp
        );

        // Handle decimal adjustments if needed
        uint32 srcChain = vaultChainIds[_storedAsset];
        uint32 dstChain = vaultChainIds[_dstAsset];

        uint8 srcDecimals = _getAssetDecimalsWithReport(_storedAsset, srcChain);
        uint8 dstDecimals = _getAssetDecimalsWithReport(_dstAsset, dstChain);

        if (srcDecimals != dstDecimals) {
            (price, ) = _adjustDecimals(price, srcDecimals, dstDecimals);
        }
    }

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
     * @param asset The address of the asset
     */
    function notifyFeedRemoval(address asset) external {
        _removeAdapter(msg.sender);
    }
}

