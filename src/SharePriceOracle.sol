// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20Metadata } from "./interfaces/IERC20Metadata.sol";
import { IOracleAdaptor, PriceReturnData } from "./interfaces/IOracleAdaptor.sol";
import { VaultReport } from "./interfaces/ISharePriceOracle.sol";

/**
 * @title MaxOracle
 * @notice A multi-adapter oracle system that supports multiple price feeds and fallback mechanisms
 * @dev This contract manages multiple oracle adapters and provides unified price conversion
 */
contract SharePriceOracle is OwnableRoles {
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

    /// @notice Mapping of stablecoin addresses to their status
    mapping(address => bool) public isStablecoin;

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
        _checkRoles(ADMIN_ROLE);
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
     * @notice Sets or unsets an asset as a stablecoin
     * @param asset The asset address
     * @param isStable Whether the asset is a stablecoin
     */
    function setStablecoin(address asset, bool isStable) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddress();
        isStablecoin[asset] = isStable;
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
     * @dev This is separated to allow for cleaner error handling
     */
    function convertStoredPrice(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) external view returns (uint256 price, uint64 timestamp) {
        // Special handling for stablecoin to stablecoin conversion
        if (isStablecoin[_storedAsset] && isStablecoin[_dstAsset]) {
            return _adjustDecimals(
                _storedPrice,
                IERC20Metadata(_storedAsset).decimals(),
                IERC20Metadata(_dstAsset).decimals()
            );
        }

        // Get asset categories
        AssetCategory srcCategory = assetCategories[_storedAsset];
        AssetCategory dstCategory = assetCategories[_dstAsset];

        // If both assets are of the same category, use direct conversion
        if (srcCategory == dstCategory && srcCategory != AssetCategory.UNKNOWN) {
            return _convertSameCategory(
                _storedPrice,
                _storedAsset,
                _dstAsset,
                srcCategory
            );
        }

        return _convertViaUSD(_storedPrice, _storedAsset, _dstAsset);
    }

    function _convertSameCategory(
        uint256 amount,
        address srcAsset,
        address dstAsset,
        AssetCategory category
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Convert through canonical asset (WBTC/WETH/USDC)
        uint256 canonicalPrice = _convertToCanonical(amount, srcAsset, category);
        (price, timestamp) = _convertFromCanonical(canonicalPrice, dstAsset, category);

        // Adjust decimals
        (price,) = _adjustDecimals(
            price,
            IERC20Metadata(srcAsset).decimals(),
            IERC20Metadata(dstAsset).decimals()
        );
    }

    function _convertViaUSD(
        uint256 _storedPrice,
        address _storedAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Get prices in USD
        (uint256 storedAssetPrice, uint256 storedAssetTimestamp, bool storedAssetInUSD) = getLatestPrice(_storedAsset, true);
        if (storedAssetPrice == 0) revert NoValidPrice();

        (uint256 dstPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);
        if (dstPrice == 0) revert NoValidPrice();

        // Convert both to USD if needed
        if (!storedAssetInUSD || !dstInUSD) {
            (storedAssetPrice, storedAssetTimestamp) = _ensureUSDPrice(
                storedAssetPrice,
                storedAssetTimestamp,
                storedAssetInUSD
            );
            (dstPrice, dstTimestamp) = _ensureUSDPrice(
                dstPrice,
                dstTimestamp,
                dstInUSD
            );
        }

        // Convert price and adjust decimals
        price = FixedPointMathLib.mulDiv(_storedPrice * PRECISION, storedAssetPrice, dstPrice);
        (price,) = _adjustDecimals(
            price,
            IERC20Metadata(_storedAsset).decimals(),
            IERC20Metadata(_dstAsset).decimals()
        );
        timestamp = uint64(storedAssetTimestamp < dstTimestamp ? storedAssetTimestamp : dstTimestamp);
    }

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
     * @notice Adjusts decimals between assets
     * @param amount The amount to adjust
     * @param srcDecimals Source asset decimals
     * @param dstDecimals Destination asset decimals
     * @return adjustedAmount The decimal-adjusted amount
     * @return timestamp Current timestamp
     */
    function _adjustDecimals(
        uint256 amount,
        uint8 srcDecimals,
        uint8 dstDecimals
    ) internal view returns (uint256 adjustedAmount, uint64 timestamp) {
        if (srcDecimals > dstDecimals) {
            uint256 scale = 10 ** (srcDecimals - dstDecimals);
            adjustedAmount = FixedPointMathLib.divWad(amount, scale);
        } else if (srcDecimals < dstDecimals) {
            uint256 scale = 10 ** (dstDecimals - srcDecimals);
            adjustedAmount = FixedPointMathLib.mulWad(amount, scale);
        } else {
            adjustedAmount = amount;
        }
        return (adjustedAmount, uint64(block.timestamp));
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
     * @notice Converts an amount to canonical form based on asset category
     * @param amount The amount to convert
     * @param asset The asset address
     * @param category The asset category
     * @return canonicalAmount The converted amount
     */
    function _convertToCanonical(
        uint256 amount,
        address asset,
        AssetCategory category
    ) internal view returns (uint256 canonicalAmount) {
        if (category == AssetCategory.BTC_LIKE) {
            if (asset == WBTC) return amount;
            (uint256 btcPrice,,) = getLatestPrice(asset, true);
            (uint256 wbtcPrice,,) = getLatestPrice(WBTC, true);
            if (btcPrice < MIN_PRICE_THRESHOLD || wbtcPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(btcPrice, block.timestamp) || !_validatePrice(wbtcPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Adjust decimals before conversion
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
            (amount,) = _adjustDecimals(amount, assetDecimals, wbtcDecimals);
            
            return FixedPointMathLib.mulDiv(amount * PRECISION, btcPrice, wbtcPrice);
        }
        
        if (category == AssetCategory.ETH_LIKE) {
            if (asset == WETH) return amount;
            (uint256 ethPrice,,) = getLatestPrice(asset, true);
            (uint256 wethPrice,,) = getLatestPrice(WETH, true);
            if (ethPrice < MIN_PRICE_THRESHOLD || wethPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(ethPrice, block.timestamp) || !_validatePrice(wethPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Adjust decimals before conversion
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            uint8 wethDecimals = IERC20Metadata(WETH).decimals();
            (amount,) = _adjustDecimals(amount, assetDecimals, wethDecimals);
            
            return FixedPointMathLib.mulDiv(amount * PRECISION, ethPrice, wethPrice);
        }
        
        if (category == AssetCategory.STABLE) {
            if (asset == USDC) return amount;
            (uint256 stablePrice,,) = getLatestPrice(asset, true);
            (uint256 usdcPrice,,) = getLatestPrice(USDC, true);
            if (stablePrice < MIN_PRICE_THRESHOLD || usdcPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(stablePrice, block.timestamp) || !_validatePrice(usdcPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Adjust decimals before conversion
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
            (amount,) = _adjustDecimals(amount, assetDecimals, usdcDecimals);
            
            return FixedPointMathLib.mulDiv(amount * PRECISION, stablePrice, usdcPrice);
        }

        return amount;
    }

    /**
     * @notice Converts an amount from canonical form to destination asset
     * @param amount The canonical amount
     * @param dstAsset The destination asset
     * @param dstCategory The destination asset category
     * @return price The converted price
     * @return timestamp The timestamp of the conversion
     */
    function _convertFromCanonical(
        uint256 amount,
        address dstAsset,
        AssetCategory dstCategory
    ) internal view returns (uint256 price, uint64 timestamp) {
        if (dstCategory == AssetCategory.BTC_LIKE) {
            if (dstAsset == WBTC) return (amount, uint64(block.timestamp));
            (uint256 btcPrice,,) = getLatestPrice(WBTC, true);
            (uint256 dstPrice,,) = getLatestPrice(dstAsset, true);
            if (btcPrice < MIN_PRICE_THRESHOLD || dstPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(btcPrice, block.timestamp) || !_validatePrice(dstPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Check price impact
            uint256 priceImpact = btcPrice > dstPrice ? 
                ((btcPrice - dstPrice) * PRECISION) / btcPrice :
                ((dstPrice - btcPrice) * PRECISION) / dstPrice;
            if (priceImpact > MAX_PRICE_IMPACT) revert PriceImpactTooHigh();
            
            // Adjust decimals after conversion
            uint8 wbtcDecimals = IERC20Metadata(WBTC).decimals();
            uint8 dstDecimals = IERC20Metadata(dstAsset).decimals();
            price = FixedPointMathLib.mulDiv(amount * PRECISION, btcPrice, dstPrice);
            (price,) = _adjustDecimals(price, wbtcDecimals, dstDecimals);
            return (price, uint64(block.timestamp));
        }

        if (dstCategory == AssetCategory.ETH_LIKE) {
            if (dstAsset == WETH) return (amount, uint64(block.timestamp));
            (uint256 ethPrice,,) = getLatestPrice(WETH, true);
            (uint256 dstPrice,,) = getLatestPrice(dstAsset, true);
            if (ethPrice < MIN_PRICE_THRESHOLD || dstPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(ethPrice, block.timestamp) || !_validatePrice(dstPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Check price impact
            uint256 priceImpact = ethPrice > dstPrice ? 
                ((ethPrice - dstPrice) * PRECISION) / ethPrice :
                ((dstPrice - ethPrice) * PRECISION) / dstPrice;
            if (priceImpact > MAX_PRICE_IMPACT) revert PriceImpactTooHigh();
            
            // Adjust decimals after conversion
            uint8 wethDecimals = IERC20Metadata(WETH).decimals();
            uint8 dstDecimals = IERC20Metadata(dstAsset).decimals();
            price = FixedPointMathLib.mulDiv(amount * PRECISION, ethPrice, dstPrice);
            (price,) = _adjustDecimals(price, wethDecimals, dstDecimals);
            return (price, uint64(block.timestamp));
        }

        if (dstCategory == AssetCategory.STABLE) {
            if (dstAsset == USDC) return (amount, uint64(block.timestamp));
            (uint256 usdcPrice,,) = getLatestPrice(USDC, true);
            (uint256 dstPrice,,) = getLatestPrice(dstAsset, true);
            if (usdcPrice < MIN_PRICE_THRESHOLD || dstPrice < MIN_PRICE_THRESHOLD) revert PriceTooLow();
            if (!_validatePrice(usdcPrice, block.timestamp) || !_validatePrice(dstPrice, block.timestamp)) 
                revert NoValidPrice();
            
            // Check price impact
            uint256 priceImpact = usdcPrice > dstPrice ? 
                ((usdcPrice - dstPrice) * PRECISION) / usdcPrice :
                ((dstPrice - usdcPrice) * PRECISION) / dstPrice;
            if (priceImpact > MAX_PRICE_IMPACT) revert PriceImpactTooHigh();
            
            // Adjust decimals after conversion
            uint8 usdcDecimals = IERC20Metadata(USDC).decimals();
            uint8 dstDecimals = IERC20Metadata(dstAsset).decimals();
            price = FixedPointMathLib.mulDiv(amount * PRECISION, usdcPrice, dstPrice);
            (price,) = _adjustDecimals(price, usdcDecimals, dstDecimals);
            return (price, uint64(block.timestamp));
        }

        return _convertViaUSD(amount, dstAsset);
    }

    /**
     * @notice Gets share price for a vault with optimized conversion
     */
    function _getDstSharePrice(
        address _vaultAddress,
        address _dstAsset
    ) internal view returns (uint256 sharePrice, uint64 timestamp) {
        IERC4626 vault = IERC4626(_vaultAddress);
        address asset = vault.asset();
        
        // Get the vault's current share price in terms of its asset
        uint256 rawSharePrice = vault.convertToAssets(PRECISION);
        
        if (asset == _dstAsset) {
            return (rawSharePrice, uint64(block.timestamp));
        }

        // Get asset categories
        AssetCategory srcCategory = assetCategories[asset];
        AssetCategory dstCategory = assetCategories[_dstAsset];

        // First convert to canonical form if needed
        uint256 canonicalPrice = _convertToCanonical(rawSharePrice, asset, srcCategory);
        
        // Then convert to destination asset
        return _convertFromCanonical(canonicalPrice, _dstAsset, dstCategory);
    }

    /**
     * @notice Converts via USD
     */
    function _convertViaUSD(
        uint256 _amount,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        (uint256 srcPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(ETH_USD_FEED, true);
        if (srcPrice == 0) revert NoValidPrice();

        (uint256 dstPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);
        if (dstPrice == 0) revert NoValidPrice();

        // Both prices should be in USD
        if (srcInUSD != dstInUSD) {
            if (!srcInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                srcPrice = FixedPointMathLib.mulDiv(srcPrice * PRECISION, ethUsdPrice, PRECISION);
                srcTimestamp = ethUsdTimestamp < srcTimestamp ? ethUsdTimestamp : srcTimestamp;
            }
            if (!dstInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                dstPrice = FixedPointMathLib.mulDiv(dstPrice * PRECISION, ethUsdPrice, PRECISION);
                dstTimestamp = ethUsdTimestamp < dstTimestamp ? ethUsdTimestamp : dstTimestamp;
            }
        }

        // Convert amount to destination asset using mulDiv
        price = FixedPointMathLib.mulDiv(_amount * PRECISION, srcPrice, dstPrice);
        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);
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

        // Cache for USDC price to optimize gas for stablecoin pairs
        uint256 usdcPrice;
        uint256 usdcTimestamp;
        bool usdcCached;

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

            // Special handling for stablecoins
            if (isStablecoin[asset]) {
                // Cache USDC price if not already cached
                if (!usdcCached && requiresUSD) {
                    (usdcPrice, usdcTimestamp,) = getLatestPrice(USDC, true);
                    usdcCached = true;
                }
                
                (uint256 price, uint256 timestamp, bool isUSD) = getLatestPrice(asset, requiresUSD);
                if (price > 0) {
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
     * @notice Helper function to batch update common pairs (e.g., ETH+stETH or USDC+DAI)
     * @param pairs Array of asset pairs to update together
     */
    struct AssetPair {
        address asset1;
        address asset2;
        bool inUSD;
    }

    function updateCommonPairs(AssetPair[] calldata pairs) external {
        for (uint256 i = 0; i < pairs.length; i++) {
            address[] memory assets = new address[](2);
            bool[] memory inUSD = new bool[](2);
            
            assets[0] = pairs[i].asset1;
            assets[1] = pairs[i].asset2;
            inUSD[0] = pairs[i].inUSD;
            inUSD[1] = pairs[i].inUSD;
            
            this.batchUpdatePrices(assets, inUSD);
        }
    }
} 