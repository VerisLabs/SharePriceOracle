// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { IERC4626 } from "./interfaces/IERC4626.sol";
import { IERC20Metadata } from "./interfaces/IERC20Metadata.sol";
import { BaseOracleAdapter } from "./libs/base/BaseOracleAdapter.sol";
import { IChainlink } from "./interfaces/chainlink/IChainlink.sol";
import { ISharePriceRouter } from "./interfaces/ISharePriceRouter.sol";

/**
 * @title SharePriceRouter
 * @notice A multi-adapter oracle system that supports multiple price feeds and fallback mechanisms
 * @dev This contract manages multiple oracle adapters and provides unified price conversion
 *
 * @dev Adapted from Curvance MIT Oracle :
 *      https://github.com/curvance/Curvance-CantinaCompetition/blob/develop/contracts/oracles/
 */
contract SharePriceRouter is ISharePriceRouter, OwnableRoles {
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
    error ExceedsMaxReports();
    error InvalidLength();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;
    /// @notice Role identifier for endpoint capabilities
    uint256 public constant ENDPOINT_ROLE = _ROLE_1;
    /// @notice Role identifier for feed capabilities
    uint256 public constant ADAPTER_ROLE = _ROLE_2;
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

    /// @notice Sequencer uptime feed address
    /// @dev Used to check L2 sequencer status
    address public sequencer;

    /// @notice Maps local assets to their price feed configurations
    /// localAsset address, adapterPriority, localAssetConfig
    mapping(address => mapping(uint8 => LocalAssetConfig)) public localAssetConfigs;

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

    /// @notice Restricts function access to admin role
    modifier onlyAdapter() {
        _checkOwnerOrRoles(ADAPTER_ROLE);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _admin) {
        if (_admin == address(0)) revert ZeroAddress();

        chainId = uint32(block.chainid);

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
        address adapter,
        address _priceFeed,
        uint8 _priority,
        bool _isUSD
    )
        external
        onlyAdmin
    {
        if (_localAsset == address(0)) revert ZeroAddress();
        if (_priceFeed == address(0)) revert ZeroAddress();
        if (adapter == address(0)) revert ZeroAddress();

        localAssetConfigs[_localAsset][_priority] =
            LocalAssetConfig({ priceFeed: _priceFeed, inUSD: _isUSD, adaptor: adapter });

        // Update highest priority if needed
        if (_priority > assetAdapterPriority[_localAsset]) {
            assetAdapterPriority[_localAsset] = _priority;
        }
        _grantRoles(adapter, ADAPTER_ROLE);

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
        emit SequencerSet(oldSequencer, _sequencer);
    }

    /**
     * @notice Sets the mapping between a cross-chain asset and its local equivalent
     * @dev Only callable by admin. Maps assets from other chains to their Base equivalents
     * @param _srcChainId The source chain ID
     * @param _srcAsset The asset address on the source chain
     * @param _localAsset The equivalent asset address on Base
     */
    function setCrossChainAssetMapping(uint32 _srcChainId, address _srcAsset, address _localAsset) external onlyAdmin {
        if (_srcChainId == chainId) revert InvalidChainId();
        if (_srcAsset == address(0) || _localAsset == address(0)) {
            revert ZeroAddress();
        }

        bytes32 key = keccak256(abi.encodePacked(_srcChainId, _srcAsset));
        crossChainAssetMap[key] = _localAsset;

        emit CrossChainAssetMapped(_srcChainId, _srcAsset, _localAsset);
    }

    /*//////////////////////////////////////////////////////////////
                           ADAPTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Notifies the router that a feed has been removed
     * @param _asset The asset whose feed was removed
     */
    function notifyFeedRemoval(address _asset) external onlyAdapter {
        uint8 assetPriority = assetAdapterPriority[_asset];

        for (uint8 i = 0; i <= assetPriority; i++) {
            delete localAssetConfigs[_asset][i];
        }

        emit LocalAssetRemoved(_asset);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if an asset is supported by the router
     * @param asset The asset address
     * @return True if the asset is supported
     */
    function isSupportedAsset(address asset) external view returns (bool) {
        LocalAssetConfig memory config = localAssetConfigs[asset][0];
        return config.priceFeed != address(0);
    }

    /**
     * @notice Checks if the sequencer is valid (for L2s)
     * @dev Returns true for L1s or if no sequencer check needed
     * @return True if the sequencer is valid
     */
    function isSequencerValid() external view returns (bool) {
        if (sequencer == address(0)) {
            return true; // No sequencer check needed (e.g. on L1)
        }

        (, int256 answer, uint256 startedAt,,) = IChainlink(sequencer).latestRoundData();

        // Answer == 0: Sequencer is up
        // Check that the sequencer is up or the grace period has passed
        if (answer != 0 || block.timestamp < startedAt + GRACE_PERIOD_TIME) {
            return false;
        }

        return true;
    }

    /**
     * @notice Generates a unique key for storing share prices
     * @dev Uses keccak256 hash of chain ID and vault address
     * @param _chainId Chain ID
     * @param _vaultAddress Vault address
     * @return The unique key as bytes32
     */
    function getPriceKey(uint32 _chainId, address _vaultAddress) external pure returns (bytes32) {
        return _getPriceKey(_chainId, _vaultAddress);
    }

    /**
     * @notice Gets the latest price for an asset
     * @param _asset The asset address
     * @param inUSD If the price should be in USD
     * @return price The latest price
     * @return hadError If any error occurred
     */
    function getLatestAssetPrice(address _asset, bool inUSD) external view returns (uint256 price, bool hadError) {
        (price,, hadError) = _getPrice(_asset, inUSD);

        if (hadError) {
            StoredAssetPrice memory storedPrice = storedAssetPrices[_asset];

            return (storedPrice.price, hadError);
        }
    }

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
        public
        view
        returns (address localAsset, uint8 localDecimals)
    {
        bytes32 key = keccak256(abi.encodePacked(_srcChainId, _srcAsset));

        localAsset = crossChainAssetMap[key];

        // Only get decimals if localAsset is not zero address
        if (localAsset == address(0)) revert AssetNotConfigured(_srcAsset);

        localDecimals = _getAssetDecimals(localAsset);

        return (localAsset, localDecimals);
    }

    function getPrice(address asset, bool inUSD) external view returns (uint256 price, bool hadError) {
        (price,, hadError) = _getPrice(asset, inUSD);
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
    )
        external
        view
        returns (VaultReport[] memory reports)
    {
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
    )
        external
        view
        returns (uint256 sharePrice, uint64 timestamp)
    {
        StoredSharePrice memory stored = storedSharePrices[_vaultAddress];

        // if it's a same chain vault
        if (_srcChainId == chainId) {
            IERC4626 vault = IERC4626(_vaultAddress);
            address asset = vault.asset();
            uint8 assetDecimals = _getAssetDecimals(asset);
            sharePrice = vault.convertToAssets(10 ** assetDecimals);

            (sharePrice, timestamp) =
                _convertPrice(sharePrice, asset, _dstAsset, assetDecimals, _getAssetDecimals(_dstAsset));
        } else {
            // no need for sharePrice > 0 already checked on updateSharePrices
            // Convert stored price to destination asset
            (sharePrice, timestamp) =
                _convertPrice(stored.sharePrice, stored.asset, _dstAsset, stored.decimals, _getAssetDecimals(_dstAsset));
        }

        // returns the oldest timestamp
        if (stored.timestamp < timestamp) {
            timestamp = stored.timestamp;
        }
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
    )
        external
        view
        returns (VaultReport memory)
    {
        bytes32 key = _getPriceKey(_srcChainId, _vaultAddress);
        return sharePrices[key];
    }

    /**
     * @notice Updates the price for the given assets
     * @param assets An array assets to update the prices for
     * @return bool if the prices were updated
     */
    function batchUpdatePrices(address[] calldata assets, bool[] calldata inUSD) external returns (bool) {
        if (assets.length != inUSD.length) revert InvalidLength();
        for (uint256 i = 0; i < assets.length; i++) {
            _updatePrice(assets[i], inUSD[i]);
        }
        return true;
    }

    /**
     * @notice Updates share prices from another chain
     * @dev Only callable by endpoint. Maps remote assets to local ones and stores prices
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata reports) external onlyEndpoint {
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
            bytes32 key = _getPriceKey(_srcChainId, report.vaultAddress);
            sharePrices[key] = report;

            (address localAsset, uint8 localDecimals) = getLocalAsset(_srcChainId, report.asset);

            // Get stored price instead of calling oracle
            StoredAssetPrice memory storedPrice = storedAssetPrices[localAsset];

            // Check if we have a valid stored price
            if (storedPrice.price == 0 || block.timestamp - storedPrice.timestamp > PRICE_STALENESS_THRESHOLD) {
                revert NoValidPrice();
            }

            storedSharePrices[report.vaultAddress] = StoredSharePrice({
                sharePrice: uint248(report.sharePrice),
                timestamp: report.lastUpdate,
                decimals: localDecimals,
                asset: localAsset
            });

            emit SharePriceUpdated(
                _srcChainId, report.vaultAddress, report.sharePrice, storedPrice.price, uint64(block.timestamp)
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getPriceKey(uint32 _chainId, address vaultAddress) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId, vaultAddress));
    }

    /**
     * @notice Get the price for an asset from configured price feeds
     * @param _asset Asset to get price for
     * @return price Latest price
     * @return timestamp Timestamp of the price
     */
    function _getPrice(
        address _asset,
        bool _inUSD
    )
        internal
        view
        returns (uint256 price, uint64 timestamp, bool hadError)
    {
        uint8 assetPriority = assetAdapterPriority[_asset];
        LocalAssetConfig memory config;
        PriceReturnData memory priceData;

        // Loops through the asset adapters to get the price
        // from the first adapter that returns a valid price
        // or until the assetPriority is reached
        for (uint8 i = 0; i <= assetPriority; ++i) {
            config = localAssetConfigs[_asset][i];

            if (config.adaptor == address(0)) continue;

            priceData = BaseOracleAdapter(config.adaptor).getPrice(_asset, _inUSD);
            return (priceData.price, uint64(block.timestamp), priceData.hadError);
        }

        // All adapters returned errors or no valid adapters found
        return (0, uint64(block.timestamp), true);
    }

    /**
     * @notice Updates an asset price
     * @dev Stores the price and Timestamp
     */
    function _updatePrice(address asset, bool inUSD) internal returns (bool) {
        (uint256 price, uint64 timestamp, bool hadError) = _getPrice(asset, inUSD);

        if (hadError) revert NoValidPrice();

        storedAssetPrices[asset] = StoredAssetPrice({ price: price, timestamp: timestamp, inUSD: inUSD });

        emit PriceStored(asset, price, timestamp, inUSD);

        return true;
    }

    /**
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
    )
        internal
        view
        returns (uint256 convertedPrice, uint64 timestamp)
    {
        // Early return for same asset
        if (_srcAsset == _dstAsset) {
            return _adjustDecimals(_price, _srcDecimals, _dstDecimals);
        }

        // Load storage values to memory once
        bool srcInUSD = storedAssetPrices[_srcAsset].inUSD;
        bool dstInUSD = storedAssetPrices[_dstAsset].inUSD;

        // Get prices for both assets
        (uint256 srcPrice, uint64 srcTime, bool srcHadError) = _getPrice(_srcAsset, srcInUSD);

        (uint256 dstPrice, uint64 dstTime, bool dstHadError) = _getPrice(_dstAsset, dstInUSD);

        // when a sharePrice is "updated" we guarantee a price had already been stored
        if (srcHadError) {
            srcPrice = storedAssetPrices[_srcAsset].price;
            srcTime = storedAssetPrices[_srcAsset].timestamp;
        }

        if (dstHadError) {
            dstPrice = storedAssetPrices[_dstAsset].price;
            dstTime = storedAssetPrices[_dstAsset].timestamp;
        }

        // First normalize the input price to 18 decimals for consistent math
        (_price,) = _adjustDecimals(_price, _srcDecimals, 18);

        // Apply price conversion based on asset types (with normalized decimals)
        if (srcInUSD && !dstInUSD) {
            // Source is USD, destination is not (e.g., converting USD to ETH)
            // Need to divide by destination price (USD/ETH)
            convertedPrice = FixedPointMathLib.mulDiv(_price, 1e18, dstPrice);
        } else if (!srcInUSD && dstInUSD) {
            // Destination is USD, source is not (e.g., converting ETH to USD)
            // Need to multiply by source price (ETH/USD)
            convertedPrice = FixedPointMathLib.mulDiv(_price, srcPrice, 1e18);
        } else {
            // USD to USD or non-USD to non-USD
            // Need to multiply by source price and divide by destination price
            convertedPrice = FixedPointMathLib.mulDiv(_price, srcPrice, dstPrice);
        }

        // Convert back to destination decimals
        (convertedPrice,) = _adjustDecimals(convertedPrice, 18, _dstDecimals);

        // Use the older timestamp for conservative staleness
        timestamp = srcTime < dstTime ? srcTime : dstTime;

        return (convertedPrice, timestamp);
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
    )
        internal
        view
        returns (uint256 adjustedPrice, uint64 timestamp)
    {
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
}
