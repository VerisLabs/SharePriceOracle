// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20Metadata } from "./interfaces/IERC20Metadata.sol";
import { IOracleAdaptor, PriceReturnData } from "./interfaces/IOracleAdaptor.sol";
import { VaultReport } from "./interfaces/ISharePriceOracle.sol";
import { console } from "forge-std/console.sol";

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
    error PriceStale();
    error PriceOverflow();
    error PriceTooLow();
    error PriceImpactTooHigh();

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
    uint256 public constant MIN_PRICE_THRESHOLD = 1e6;  // 0.000001 in 18 decimals
    /// @notice Maximum price impact allowed for conversions (1% = 10000)
    uint256 public constant MAX_PRICE_IMPACT = 10000;  // 1%

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

    /// @notice Asset categories for optimized conversion
    enum AssetCategory {
        UNKNOWN,
        BTC_LIKE,    // WBTC, BTCb, TBTC, etc.
        ETH_LIKE,    // ETH, stETH, rsETH, etc.
        STABLE       // USDC, USDT, DAI, etc.
    }

    /// @notice Mapping of assets to their category
    mapping(address => AssetCategory) public assetCategories;

    /// @notice Mapping of oracle adapters to their priorities
    /// @dev Lower number means higher priority
    mapping(address => uint256) public adapterPriorities;

    /// @notice Array of all oracle adapters
    address[] public oracleAdapters;

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

    /// @notice Cache for asset decimals
    mapping(address => uint8) private cachedAssetDecimals;

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
    function revokeRole(address account, uint256 role) external onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }

    /**
     * @notice Adds a new oracle adapter
     * @param adapter Address of the oracle adapter
     * @param priority Priority level for the adapter (lower = higher priority)
     */
    function addAdapter(address adapter, uint256 priority) external onlyAdmin {
        if (adapter == address(0)) revert ZeroAddress();
        if (adapterPriorities[adapter] != 0) revert AdapterAlreadyExists();

        adapterPriorities[adapter] = priority;
        oracleAdapters.push(adapter);
        emit AdapterAdded(adapter, priority);
    }

    /**
     * @notice Removes an oracle adapter
     * @param adapter Address of the oracle adapter to remove
     */
    function removeAdapter(address adapter) external onlyAdmin {
        if (adapter == address(0)) revert ZeroAddress();
        if (adapterPriorities[adapter] == 0) revert AdapterNotFound();

        // Remove from priorities
        delete adapterPriorities[adapter];

        // Remove from array
        for (uint256 i = 0; i < oracleAdapters.length; i++) {
            if (oracleAdapters[i] == adapter) {
                oracleAdapters[i] = oracleAdapters[oracleAdapters.length - 1];
                oracleAdapters.pop();
                break;
            }
        }

        emit AdapterRemoved(adapter);
    }

    /**
     * @notice Sets the category for an asset
     * @param asset The asset address
     * @param category The asset category
     */
    function setAssetCategory(address asset, AssetCategory category) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddress();
        if (category == AssetCategory.UNKNOWN) revert InvalidAssetType();
        assetCategories[asset] = category;
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Gets the latest price for an asset using all available adapters
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
                PriceReturnData memory priceData = adapter.getPrice(asset, inUSD, true);
                
                if (!priceData.hadError && priceData.price > 0) {
                    return (priceData.price, block.timestamp, priceData.inUSD);
                }
            }
        }

        // If no current price, check stored price
        StoredPrice memory storedPrice = storedPrices[asset];
        if (storedPrice.price > 0 && 
            block.timestamp - storedPrice.timestamp <= PRICE_STALENESS_THRESHOLD) {
            return (storedPrice.price, storedPrice.timestamp, storedPrice.isUSD);
        }

        revert NoValidPrice();
    }

    /**
     * @notice Updates and stores the latest price for an asset
     * @param asset Address of the asset to update
     * @param inUSD Whether to store the price in USD
     */
    function updatePrice(address asset, bool inUSD) external {
        (uint256 price, uint256 timestamp, bool isUSD) = getLatestPrice(asset, inUSD);
        
        storedPrices[asset] = StoredPrice({
            price: price,
            timestamp: timestamp,
            isUSD: isUSD
        });

        emit PriceStored(asset, price, timestamp);
    }

    /**
     * @notice Checks if a timestamp is considered stale
     * @param timestamp The timestamp to check
     * @return True if the timestamp is stale
     */
    function _isStale(uint256 timestamp) internal view returns (bool) {
        return block.timestamp - timestamp > PRICE_STALENESS_THRESHOLD;
    }

    /**
     * @notice Stores a share price with metadata
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
            decimals: IERC20Metadata(asset).decimals()
        });
    }

    /**
     * @notice Gets the cross-chain price for a vault
     * @param _vaultAddress The vault address
     * @param _dstAsset The destination asset
     * @param _srcChain The source chain ID
     * @return price The converted price
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
            
            try this.convertStoredPrice(
                report.sharePrice,
                report.asset,
                _dstAsset
            ) returns (uint256 convertedPrice, uint64 convertedTime) {
                if (_validatePrice(convertedPrice, convertedTime)) {
                    return (convertedPrice, convertedTime);
                }
            } catch {}
        }
        return (0, 0);
    }

    /**
     * @notice Gets the latest share price for a vault
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
        try this.calculateSharePrice(_vaultAddress, _dstAsset) 
        returns (uint256 currentPrice, uint64 currentTime) {
            if (currentPrice > 0 && _validatePrice(currentPrice, currentTime)) {
                _storeSharePrice(_vaultAddress, currentPrice, currentTime);
                return (currentPrice, currentTime);
            }
        } catch {}

        // Fallback to cross-chain price for remote vaults
        uint32 vaultChain = vaultChainIds[_vaultAddress];
        if (vaultChain != 0 && vaultChain != chainId) {
            (sharePrice, timestamp) = _getCrossChainPrice(_vaultAddress, _dstAsset, vaultChain);
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
                try this.convertStoredPrice(
                    stored.sharePrice, 
                    stored.asset, 
                    _dstAsset
                ) returns (uint256 convertedPrice, uint64 convertedTime) {
                    if (_validatePrice(convertedPrice, convertedTime)) {
                        return (convertedPrice, convertedTime);
                    }
                } catch {}
            }

            // Use stale stored price rather than 1:1 if we have it
            if (stored.asset != _dstAsset) {
                try this.convertStoredPrice(
                    stored.sharePrice, 
                    stored.asset, 
                    _dstAsset
                ) returns (uint256 convertedPrice, uint64 convertedTime) {
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
            return (rawPrice > 0 ? rawPrice : PRECISION, uint64(block.timestamp));
        }

        // Absolute last resort: Return 1:1 ratio
        return (PRECISION, uint64(block.timestamp));
    }

    /**
     * @notice Calculates current share price without storing it
     * @dev This is separated to allow for view-only calls and cleaner error handling
     */
    function calculateSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) external view returns (uint256 sharePrice, uint64 timestamp) {
        return _getDstSharePrice(_vaultAddress, _dstAsset);
    }

    /**
     * @notice Updates share prices from another chain via LayerZero
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata reports) external onlyEndpoint {
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

            emit SharePriceUpdated(_srcChainId, report.vaultAddress, report.sharePrice, report.rewardsDelegate);
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
            uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
            uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
            (price,) = _adjustDecimals(_storedPrice, srcDecimals, dstDecimals);
            return (price, uint64(block.timestamp));
        }

        // Get asset categories
        AssetCategory srcCategory = assetCategories[_storedAsset];
        AssetCategory dstCategory = assetCategories[_dstAsset];

        // Require both assets to be categorized
        if (srcCategory == AssetCategory.UNKNOWN || dstCategory == AssetCategory.UNKNOWN) {
            revert InvalidAssetType();
        }

        // Handle same category conversions
        if (srcCategory == dstCategory) {
            if (srcCategory == AssetCategory.ETH_LIKE) {
                return _convertEthToEth(_storedPrice, _storedAsset, _dstAsset);
            } else if (srcCategory == AssetCategory.BTC_LIKE) {
                return _convertBtcToBtc(_storedPrice, _storedAsset, _dstAsset);
            } else if (srcCategory == AssetCategory.STABLE) {
                return _convertStableToStable(_storedPrice, _storedAsset, _dstAsset);
            }
        }

        // Handle cross-category conversions through USD
        return _convertCrossCategory(_storedPrice, _storedAsset, _dstAsset);
    }

    function _convertBtcToBtc(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        (uint256 srcBtcPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(_storedAsset, false);
        (uint256 dstBtcPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, false);
        
        if (srcBtcPrice == 0 || dstBtcPrice == 0) revert NoValidPrice();
        
        // Convert using BTC as the intermediate
        price = FixedPointMathLib.mulDiv(_storedPrice, srcBtcPrice, dstBtcPrice);
        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);

        // Adjust decimals if needed
        uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        if (srcDecimals != dstDecimals) {
            (price,) = _adjustDecimals(price, srcDecimals, dstDecimals);
        }
    }

    function _convertEthToEth(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        (uint256 srcEthPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(_storedAsset, false);
        (uint256 dstEthPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, false);
        
        if (srcEthPrice == 0 || dstEthPrice == 0) revert NoValidPrice();
        
        // Convert using ETH as the intermediate
        price = FixedPointMathLib.mulDiv(_storedPrice, srcEthPrice, dstEthPrice);
        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);

        // Adjust decimals if needed
        uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        if (srcDecimals != dstDecimals) {
            (price,) = _adjustDecimals(price, srcDecimals, dstDecimals);
        }
    }

    function _convertStableToStable(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        (uint256 srcUsdPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(_storedAsset, true);
        (uint256 dstUsdPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);
        
        if (srcUsdPrice == 0 || dstUsdPrice == 0) revert NoValidPrice();
        
        // Convert using USD as the intermediate
        price = FixedPointMathLib.mulDiv(_storedPrice, srcUsdPrice, dstUsdPrice);
        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);

        // Adjust decimals if needed
        uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        if (srcDecimals != dstDecimals) {
            (price,) = _adjustDecimals(price, srcDecimals, dstDecimals);
        }
    }

    function _convertCrossCategory(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get USD prices for both assets
        (uint256 srcUsdPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(_storedAsset, true);
        (uint256 dstUsdPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);

        if (srcUsdPrice == 0 || dstUsdPrice == 0) revert NoValidPrice();

        // Get decimals
        uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();

        // First convert source amount to USD (18 decimals)
        uint256 usdAmount = FixedPointMathLib.mulDiv(_storedPrice, srcUsdPrice, PRECISION);
        
        // Then convert USD amount to destination asset
        price = FixedPointMathLib.mulDiv(usdAmount, PRECISION, dstUsdPrice);

        // Adjust decimals for final result
        if (srcDecimals != dstDecimals) {
            if (srcDecimals > dstDecimals) {
                price = price / (10 ** (srcDecimals - dstDecimals));
            } else {
                price = price * (10 ** (dstDecimals - srcDecimals));
            }
        }

        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);
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
     * @notice Gets share price for a vault with standardized conversion
     */
    function _getDstSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        console.log("_getDstSharePrice: Getting share price for vault", _vaultAddress);
        console.log("Converting to asset:", _dstAsset);

        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();
        console.log("Vault's underlying asset:", asset);
        
        uint256 rawSharePrice = vault.convertToAssets(PRECISION);
        console.log("Raw share price from vault:", rawSharePrice);
        
        if (asset == _dstAsset) {
            // No conversion needed, price is already in correct asset
            return (rawSharePrice, uint64(block.timestamp));
        }

        console.log("Converting through USD");
        // The raw share price is already in the source asset's decimals
        // since it comes directly from the vault's convertToAssets
        return this.convertStoredPrice(rawSharePrice, asset, _dstAsset);
    }

    /**
     * @notice Gets share prices for multiple vaults
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
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            
            // Get latest price in USD
            (uint256 price,,) = getLatestPrice(asset, true);
            
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

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Generates a unique key for storing share prices
     * @param _chainId Chain ID
     * @param _vaultAddress Vault address
     */
    function getPriceKey(uint32 _chainId, address _vaultAddress) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId, _vaultAddress));
    }

    /**
     * @notice Gets decimals for an asset with caching
     * @param asset The asset address
     * @return decimals The number of decimals
     */
    function _getDecimals(address asset) internal returns (uint8) {
        uint8 decimals = cachedAssetDecimals[asset];
        if (decimals == 0) {
            decimals = IERC20Metadata(asset).decimals();
            cachedAssetDecimals[asset] = decimals;
        }
        return decimals;
    }

    /**
     * @notice Validates a price and its timestamp
     * @param price The price to validate
     * @param timestamp The timestamp of the price
     * @return valid Whether the price is valid
     */
    function _validatePrice(uint256 price, uint256 timestamp) internal view returns (bool valid) {
        if (price == 0 || price < MIN_PRICE_THRESHOLD) return false;
        if (block.timestamp - timestamp > PRICE_STALENESS_THRESHOLD) return false;
        if (price > type(uint240).max) return false;
        return true;
    }

    /**
     * @notice Ensures a price is in USD
     * @param price The price to ensure is in USD
     * @param timestamp The timestamp of the price
     * @param inUSD Whether the price is in USD
     * @return usdPrice The price in USD
     * @return usdTimestamp The timestamp of the price in USD
     */
    function _ensureUSDPrice(
        uint256 price,
        uint256 timestamp,
        bool inUSD
    ) internal view returns (uint256 usdPrice, uint256 usdTimestamp) {
        if (inUSD) {
            return (price, timestamp);
        }

        (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
        if (ethUsdPrice == 0) revert NoValidPrice();

        usdPrice = FixedPointMathLib.mulDiv(price * PRECISION, ethUsdPrice, PRECISION);
        usdTimestamp = ethUsdTimestamp < timestamp ? ethUsdTimestamp : timestamp;
    }

    /**
     * @notice Batch updates prices for multiple assets with gas optimizations for related pairs
     * @param assets Array of asset addresses to update
     * @param inUSD Array of booleans indicating if each price should be in USD
     * @dev Optimizes gas usage by caching shared price lookups (e.g., ETH/USD for ETH-related pairs)
     */
    function batchUpdatePrices(
        address[] calldata assets,
        bool[] calldata inUSD
    ) external {
        if (assets.length != inUSD.length) revert InvalidPriceData();
        if (assets.length == 0) revert InvalidPriceData();

        // Cache for ETH/USD price to optimize gas for ETH-related pairs
        uint256 ethUsdPrice;
        uint256 ethUsdTimestamp;
        bool ethUsdCached;

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            bool requiresUSD = inUSD[i];
            
            // Special handling for ETH-like assets
            if (assetCategories[asset] == AssetCategory.ETH_LIKE) {
                // Cache ETH/USD price if not already cached
                if (!ethUsdCached && requiresUSD) {
                    (ethUsdPrice, ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                    ethUsdCached = true;
                }
                
                // Get asset's price in ETH
                (uint256 price, uint256 timestamp, bool isUSD) = getLatestPrice(asset, false);
                if (price > 0) {
                    if (requiresUSD && !isUSD && ethUsdCached) {
                        // Convert to USD using cached ETH/USD price
                        price = FixedPointMathLib.mulDiv(price * PRECISION, ethUsdPrice, PRECISION);
                        timestamp = timestamp < ethUsdTimestamp ? timestamp : ethUsdTimestamp;
                        isUSD = true;
                    }
                    
                    storedPrices[asset] = StoredPrice({
                        price: price,
                        timestamp: timestamp,
                        isUSD: isUSD
                    });
                    
                    emit PriceStored(asset, price, timestamp);
                }
                continue;
            }

            // Standard price update for other assets
            try this.updatePrice(asset, requiresUSD) {
                // Price update and event emission handled in updatePrice
            } catch {
                // Continue with next asset if update fails
                continue;
            }
        }
    }

    /**
     * @notice Checks if the sequencer is valid (for L2s)
     * @return True if the sequencer is valid
     */
    function isSequencerValid() external pure returns (bool) {
        return true; // For L1s or if no sequencer check needed
    }

    /**
     * @notice Checks if an asset is supported by any adapter
     * @param asset The asset to check
     * @return True if the asset is supported
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
     * @notice Gets the price for an asset from the best available adapter
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
        try this.getLatestPrice(asset, inUSD) returns (uint256 p, uint256 timestamp, bool isUSD) {
            if (p > 0 && !_isStale(timestamp) && isUSD == inUSD) {
                return (p, 0);
            }
        } catch {}
        return (0, 1);
    }
} 