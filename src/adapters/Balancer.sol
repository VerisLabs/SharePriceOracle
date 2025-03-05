// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { BaseOracleAdapter } from "../libs/base/BaseOracleAdapter.sol";
import { ERC20 } from "@solady/tokens/ERC20.sol";
import { ISharePriceRouter, PriceReturnData } from "../interfaces/ISharePriceRouter.sol";
import { IBalancerWeightedPool } from "../interfaces/balancer/IBalancerWeightedPool.sol";
import { IBalancerVault } from "../interfaces/balancer/IBalancerVault.sol";

/**
 * @title BalancerAdapter
 * @notice Adapter contract for fetching and normalizing price data from Balancer weighted pools
 * @dev Handles pricing of Balancer Pool Tokens (BPT) using geometric mean of underlying assets
 */
contract BalancerAdapter is BaseOracleAdapter {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Configuration data for Balancer pool price sources
    /// @param pool Address of the Balancer weighted pool
    /// @param isConfigured Whether pool is configured (false = unconfigured, true = configured)
    /// @param heartbeat Maximum time between price updates (0 = DEFAULT_HEART_BEAT)
    struct AdapterData {
        IBalancerWeightedPool pool;
        bool isConfigured;
        uint256 heartbeat;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Default heartbeat duration if none specified
    uint256 public constant DEFAULT_HEART_BEAT = 1 days;

    /// @notice Balancer vault contract
    IBalancerVault public immutable BALANCER_VAULT;

    /// @notice Chain WETH address
    address public immutable WETH;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of BPT addresses to their pool data
    mapping(address => AdapterData) public adapterData;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event BalancerPoolAdded(address bpt, AdapterData poolConfig, bool isUpdate);
    event BalancerPoolRemoved(address bpt);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BalancerAdapter__AssetNotSupported();
    error BalancerAdapter__InvalidHeartbeat();
    error BalancerAdapter__InvalidPool();
    error BalancerAdapter__StalePrice();
    error BalancerAdapter__PriceError();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _admin,
        address _oracle,
        address _oracleRouter,
        address _balancerVault,
        address _weth
    )
        BaseOracleAdapter(_admin, _oracle, _oracleRouter)
    {
        BALANCER_VAULT = IBalancerVault(_balancerVault);
        WETH = _weth;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/


    function getPrice(address asset, bool inUSD) external view override returns (PriceReturnData memory pData) {
        // Validate we support pricing this BPT
        if (!isSupportedAsset[asset]) {
            revert BalancerAdapter__AssetNotSupported();
        }

        AdapterData memory data = adapterData[asset];
        IBalancerWeightedPool pool = data.pool;

        // Get pool tokens and weights
        (address[] memory tokens,,) = BALANCER_VAULT.getPoolTokens(pool.getPoolId());
        uint256[] memory weights = pool.getNormalizedWeights();
        
        // Calculate geometric mean of underlying token prices
        uint256 geometricMean = WAD;
        ISharePriceRouter router = ISharePriceRouter(ORACLE_ROUTER_ADDRESS);

        for (uint256 i = 0; i < tokens.length; i++) {
            // Get underlying token price
            (uint256 tokenPrice, uint256 errorCode) = router.getPrice(tokens[i], inUSD);
            
            if (errorCode > 0) {
                pData.hadError = true;
                return pData;
            }

            // Update geometric mean
            geometricMean = (geometricMean * (tokenPrice ** weights[i])) / (WAD ** weights[i]);
        }

        // Calculate BPT price using geometric mean and pool invariant
        uint256 invariant = pool.getLastInvariant();
        uint256 totalSupply = ERC20(asset).totalSupply();
        uint256 price = (geometricMean * invariant) / totalSupply;

        // Check staleness
        if (block.timestamp - pool.getLastInvariantCalculationTimestamp() > data.heartbeat) {
            revert BalancerAdapter__StalePrice();
        }

        if (price == 0) {
            revert BalancerAdapter__PriceError();
        }

        pData.price = uint240(price);
        pData.inUSD = inUSD;
    }

    /**
     * @notice Adds or updates a Balancer pool for pricing
     * @param bpt Address of the Balancer Pool Token
     * @param pool Address of the Balancer weighted pool
     * @param heartbeat Maximum allowed time between updates
     */
    function addAsset(address bpt, address pool, uint256 heartbeat) external {
        _checkOraclePermissions();

        if (heartbeat != 0 && heartbeat > DEFAULT_HEART_BEAT) {
            revert BalancerAdapter__InvalidHeartbeat();
        }

        // Validate pool configuration
        if (!_isValidWeightedPool(pool)) {
            revert BalancerAdapter__InvalidPool();
        }

        AdapterData storage data = adapterData[bpt];
        
        data.pool = IBalancerWeightedPool(pool);
        data.heartbeat = heartbeat != 0 ? heartbeat : DEFAULT_HEART_BEAT;
        data.isConfigured = true;

        bool isUpdate = isSupportedAsset[bpt];
        isSupportedAsset[bpt] = true;

        emit BalancerPoolAdded(bpt, data, isUpdate);
    }

    /**
     * @notice Removes price feed support for a Balancer pool
     * @param bpt Address of the BPT to remove
     */
    function removeAsset(address bpt) external override {
        _checkOraclePermissions();

        if (!isSupportedAsset[bpt]) {
            revert BalancerAdapter__AssetNotSupported();
        }

        delete isSupportedAsset[bpt];
        delete adapterData[bpt];

        ISharePriceRouter(ORACLE_ROUTER_ADDRESS).notifyFeedRemoval(bpt);
        emit BalancerPoolRemoved(bpt);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates that a pool is a valid Balancer weighted pool
     * @param pool Address to validate
     * @return bool True if valid weighted pool
     */
    function _isValidWeightedPool(address pool) internal view returns (bool) {
        try IBalancerWeightedPool(pool).getNormalizedWeights() returns (uint256[] memory) {
            return true;
        } catch {
            return false;
        }
    }
} 