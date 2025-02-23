// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20Metadata } from "./interfaces/IERC20Metadata.sol";
import { IOracleAdaptor, PriceReturnData } from "./interfaces/IOracleAdaptor.sol";
import { VaultReport } from "./interfaces/ISharePriceOracle.sol";
import { VaultLib } from "./libs/VaultLib.sol";
import { PriceConversionLib } from "./libs/PriceConversionLib.sol";

/**
 * @title MaxOracle
 * @notice A multi-adapter oracle system that supports multiple price feeds and fallback mechanisms
 * @dev This contract manages multiple oracle adapters and provides unified price conversion
 */
contract MaxOracle is OwnableRoles {
    using FixedPointMathLib for uint256;
    using VaultLib for IERC4626;

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

    /// @notice Asset types for optimized conversion
    enum AssetType {
        OTHER,
        STABLE,
        BTC,
        ETH
    }

    /// @notice Mapping of assets to their type
    mapping(address => AssetType) public assetTypes;

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

        // Set up base asset types
        assetTypes[_usdc] = AssetType.STABLE;
        assetTypes[_wbtc] = AssetType.BTC;
        assetTypes[_weth] = AssetType.ETH;

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
     * @notice Sets the asset type for optimized conversion
     * @param asset The asset address
     * @param assetType The type of the asset
     */
    function setAssetType(address asset, AssetType assetType) external onlyAdmin {
        if (asset == address(0)) revert ZeroAddress();
        assetTypes[asset] = assetType;
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
        uint32 vaultChain = vaultChainIds[_vaultAddress];
        
        // If it's a cross-chain vault, handle differently
        if (vaultChain != 0 && vaultChain != chainId) {
            bytes32 key = getPriceKey(vaultChain, _vaultAddress);
            VaultReport memory report = sharePrices[key];
            
            if (report.sharePrice > 0) {
                if (report.asset == _dstAsset) {
                    return (report.sharePrice, report.lastUpdate);
                }
                
                // Try to convert the report price
                try this.convertStoredPrice(
                    report.sharePrice,
                    report.asset,
                    _dstAsset
                ) returns (uint256 convertedPrice, uint64 convertedTime) {
                    return (convertedPrice, convertedTime);
                } catch {
                    // Fall through to final fallbacks if conversion fails
                }
            }
        }

        // For local vaults or if cross-chain price not available
        // First try: Current calculation with adapters
        try this.calculateSharePrice(_vaultAddress, _dstAsset) returns (uint256 price, uint64 time) {
            // Store the successful price calculation
            IERC4626 vault = IERC4626(_vaultAddress);
            address asset = vault.asset();
            
            storedSharePrices[_vaultAddress] = StoredSharePrice({
                sharePrice: price,
                timestamp: time,
                asset: asset,
                decimals: IERC20Metadata(asset).decimals()
            });

            return (price, time);
        } catch {
            // Second try: Check stored share prices
            StoredSharePrice memory stored = storedSharePrices[_vaultAddress];
            
            if (stored.sharePrice > 0) {
                if (stored.asset == _dstAsset) {
                    return (stored.sharePrice, uint64(stored.timestamp));
                }
                
                // Try to convert the stored price
                try this.convertStoredPrice(
                    stored.sharePrice, 
                    stored.asset, 
                    _dstAsset
                ) returns (uint256 convertedPrice, uint64 convertedTime) {
                    return (convertedPrice, convertedTime);
                } catch {}
            }

            // Third try: Check cross-chain prices from sharePrices mapping
            bytes32 key = getPriceKey(chainId, _vaultAddress);
            VaultReport memory report = sharePrices[key];
            
            if (report.sharePrice > 0) {
                if (report.asset == _dstAsset) {
                    return (report.sharePrice, report.lastUpdate);
                }
                
                // Try to convert the report price
                try this.convertStoredPrice(
                    report.sharePrice,
                    report.asset,
                    _dstAsset
                ) returns (uint256 convertedPrice, uint64 convertedTime) {
                    return (convertedPrice, convertedTime);
                } catch {}
            }

            // Final fallback: Use raw share price from vault
            // This at least maintains the share/asset ratio even if we can't price it
            IERC4626 vault = IERC4626(_vaultAddress);
            address asset = vault.asset();
            
            if (asset == _dstAsset) {
                uint256 rawPrice = vault.convertToAssets(PRECISION);
                return (rawPrice > 0 ? rawPrice : PRECISION, uint64(block.timestamp));
            }

            // Absolute last resort: Return 1:1 ratio
            // This is better than reverting or returning 0, which could enable attacks
            return (PRECISION, uint64(block.timestamp));
        }
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
            // Just adjust decimals between stablecoins
            uint8 srcDecimals = IERC20Metadata(_storedAsset).decimals();
            uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
            
            if (srcDecimals > dstDecimals) {
                price = _storedPrice / (10 ** (srcDecimals - dstDecimals));
            } else if (srcDecimals < dstDecimals) {
                price = _storedPrice * (10 ** (dstDecimals - srcDecimals));
            } else {
                price = _storedPrice;
            }
            return (price, uint64(block.timestamp));
        }

        // Regular price conversion for non-stablecoin pairs
        (uint256 storedAssetPrice, uint256 storedAssetTimestamp, bool storedAssetInUSD) = getLatestPrice(_storedAsset, true);
        if (storedAssetPrice == 0) revert NoValidPrice();

        (uint256 dstPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);
        if (dstPrice == 0) revert NoValidPrice();

        // Both prices should be in the same denomination (USD)
        if (storedAssetInUSD != dstInUSD) {
            // If one is in ETH and other in USD, convert both to USD
            if (!storedAssetInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                storedAssetPrice = (storedAssetPrice * ethUsdPrice) / PRECISION;
                storedAssetTimestamp = ethUsdTimestamp < storedAssetTimestamp ? ethUsdTimestamp : storedAssetTimestamp;
            }
            if (!dstInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                dstPrice = (dstPrice * ethUsdPrice) / PRECISION;
                dstTimestamp = ethUsdTimestamp < dstTimestamp ? ethUsdTimestamp : dstTimestamp;
            }
        }

        // Convert stored price to destination asset
        price = (_storedPrice * storedAssetPrice) / dstPrice;
        timestamp = uint64(storedAssetTimestamp < dstTimestamp ? storedAssetTimestamp : dstTimestamp);
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

            // Store the price for fallback
            storedPrices[report.vaultAddress] = StoredPrice({
                price: report.sharePrice,
                timestamp: block.timestamp,
                isUSD: true  // Assuming cross-chain prices are in USD
            });

            emit SharePriceUpdated(_srcChainId, report.vaultAddress, report.sharePrice, report.rewardsDelegate);
        }
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
     * @notice Gets share price for a vault with optimized conversion for base assets
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

        // Get asset types for optimized conversion
        AssetType srcType = assetTypes[asset];
        AssetType dstType = assetTypes[_dstAsset];

        // Handle special cases for base assets
        if (srcType != AssetType.OTHER && dstType != AssetType.OTHER) {
            // Both assets are base assets, we can optimize
            if (srcType == dstType) {
                // Same type (e.g., USDC to DAI, or WBTC to renBTC)
                return _convertSameBaseType(rawSharePrice, asset, _dstAsset);
            }

            // Different base types, use optimized conversion
            return _convertBaseAssets(rawSharePrice, asset, _dstAsset, srcType, dstType);
        }

        // Special handling for stablecoin to stablecoin conversion
        if (isStablecoin[asset] && isStablecoin[_dstAsset]) {
            return _convertStableToStable(rawSharePrice, asset, _dstAsset);
        }

        // Regular price conversion for other assets
        return _convertViaUSD(rawSharePrice, asset, _dstAsset);
    }

    /**
     * @notice Converts between assets of the same base type
     */
    function _convertSameBaseType(
        uint256 _amount,
        address _srcAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Just handle decimal differences
        uint8 srcDecimals = IERC20Metadata(_srcAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        
        if (srcDecimals > dstDecimals) {
            price = _amount / (10 ** (srcDecimals - dstDecimals));
        } else if (srcDecimals < dstDecimals) {
            price = _amount * (10 ** (dstDecimals - srcDecimals));
        } else {
            price = _amount;
        }
        return (price, uint64(block.timestamp));
    }

    /**
     * @notice Converts between different base asset types
     */
    function _convertBaseAssets(
        uint256 _amount,
        address _srcAsset,
        address _dstAsset,
        AssetType _srcType,
        AssetType _dstType
    ) internal view returns (uint256 price, uint64 timestamp) {
        if (_srcType == AssetType.STABLE) {
            if (_dstType == AssetType.ETH) {
                // STABLE -> ETH: Use ETH/USD price
                (uint256 ethPrice,,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, PRECISION * PRECISION / ethPrice);
            }
            if (_dstType == AssetType.BTC) {
                // STABLE -> BTC: Use BTC/USD price
                (uint256 btcPrice,,) = getLatestPrice(WBTC, true);
                if (btcPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, PRECISION * PRECISION / btcPrice);
            }
        }
        
        if (_srcType == AssetType.ETH) {
            if (_dstType == AssetType.STABLE) {
                // ETH -> STABLE: Use ETH/USD price
                (uint256 ethPrice,,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, ethPrice);
            }
            if (_dstType == AssetType.BTC) {
                // ETH -> BTC: Use ETH/USD and BTC/USD prices
                (uint256 ethPrice,,) = getLatestPrice(ETH_USD_FEED, true);
                (uint256 btcPrice,,) = getLatestPrice(WBTC, true);
                if (ethPrice == 0 || btcPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, ethPrice * PRECISION / btcPrice);
            }
        }

        if (_srcType == AssetType.BTC) {
            if (_dstType == AssetType.STABLE) {
                // BTC -> STABLE: Use BTC/USD price
                (uint256 btcPrice,,) = getLatestPrice(WBTC, true);
                if (btcPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, btcPrice);
            }
            if (_dstType == AssetType.ETH) {
                // BTC -> ETH: Use BTC/USD and ETH/USD prices
                (uint256 btcPrice,,) = getLatestPrice(WBTC, true);
                (uint256 ethPrice,,) = getLatestPrice(ETH_USD_FEED, true);
                if (btcPrice == 0 || ethPrice == 0) revert NoValidPrice();
                return _convertWithDecimals(_amount, _srcAsset, _dstAsset, btcPrice * PRECISION / ethPrice);
            }
        }

        revert NoValidPrice();
    }

    /**
     * @notice Helper function to handle decimal adjustments in conversions
     */
    function _convertWithDecimals(
        uint256 _amount,
        address _srcAsset,
        address _dstAsset,
        uint256 _rate
    ) internal view returns (uint256 price, uint64 timestamp) {
        uint8 srcDecimals = IERC20Metadata(_srcAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        
        uint256 adjustedAmount = _amount * _rate / PRECISION;
        
        if (srcDecimals > dstDecimals) {
            price = adjustedAmount / (10 ** (srcDecimals - dstDecimals));
        } else if (srcDecimals < dstDecimals) {
            price = adjustedAmount * (10 ** (dstDecimals - srcDecimals));
        } else {
            price = adjustedAmount;
        }
        return (price, uint64(block.timestamp));
    }

    /**
     * @notice Converts between stablecoins
     */
    function _convertStableToStable(
        uint256 _amount,
        address _srcAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Just handle decimal differences
        uint8 srcDecimals = IERC20Metadata(_srcAsset).decimals();
        uint8 dstDecimals = IERC20Metadata(_dstAsset).decimals();
        
        if (srcDecimals > dstDecimals) {
            price = _amount / (10 ** (srcDecimals - dstDecimals));
        } else if (srcDecimals < dstDecimals) {
            price = _amount * (10 ** (dstDecimals - srcDecimals));
        } else {
            price = _amount;
        }
        return (price, uint64(block.timestamp));
    }

    /**
     * @notice Converts via USD
     */
    function _convertViaUSD(
        uint256 _amount,
        address _srcAsset,
        address _dstAsset
    ) internal view returns (uint256 price, uint64 timestamp) {
        // Regular price conversion for other assets
        (uint256 srcPrice, uint256 srcTimestamp, bool srcInUSD) = getLatestPrice(_srcAsset, true);
        if (srcPrice == 0) revert NoValidPrice();

        (uint256 dstPrice, uint256 dstTimestamp, bool dstInUSD) = getLatestPrice(_dstAsset, true);
        if (dstPrice == 0) revert NoValidPrice();

        // Both prices should be in the same denomination (USD)
        if (srcInUSD != dstInUSD) {
            // If one is in ETH and other in USD, convert both to USD
            if (!srcInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                srcPrice = (srcPrice * ethUsdPrice) / PRECISION;
                srcTimestamp = ethUsdTimestamp < srcTimestamp ? ethUsdTimestamp : srcTimestamp;
            }
            if (!dstInUSD) {
                (uint256 ethUsdPrice, uint256 ethUsdTimestamp,) = getLatestPrice(ETH_USD_FEED, true);
                if (ethUsdPrice == 0) revert NoValidPrice();
                dstPrice = (dstPrice * ethUsdPrice) / PRECISION;
                dstTimestamp = ethUsdTimestamp < dstTimestamp ? ethUsdTimestamp : dstTimestamp;
            }
        }

        // Convert amount to destination asset
        price = (_amount * srcPrice) / dstPrice;
        timestamp = uint64(srcTimestamp < dstTimestamp ? srcTimestamp : dstTimestamp);
    }
} 