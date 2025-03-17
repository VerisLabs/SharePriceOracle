// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ISharePriceOracle } from "../../interfaces/ISharePriceOracle.sol";
import { OwnableRoles } from "@solady/auth/OwnableRoles.sol";

/**
 * @title BaseOracleAdapter
 * @notice Base contract for oracle adapters that fetch and normalize asset prices
 */
abstract contract BaseOracleAdapter is OwnableRoles {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event RoleGranted(address account, uint256 role);
    event RoleRevoked(address account, uint256 role);

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for Oracle operations
    uint256 public constant ORACLE_ROLE = _ROLE_1;

    /// @notice Scaling factor for 18 decimal precision
    uint256 constant WAD = 1e18;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the Oracle Router contract
    address public ORACLE_ROUTER_ADDRESS;

    /// @notice Maps assets to their support status in the Oracle Adapter
    /// @dev Asset address => Support status (true = supported)
    mapping(address => bool) public isSupportedAsset;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error ZeroAddress();
    error InvalidRole();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the BaseOracleAdapter
     * @param _admin Address that will have admin privileges
     * @param _oracle Address that will have oracle privileges
     * @param _oracleRouter Address of the Oracle Router contract
     */
    constructor(address _admin, address _oracle, address _oracleRouter) {
        if (_admin == address(0)) revert ZeroAddress();
        if (_oracle == address(0)) revert ZeroAddress();

        ORACLE_ROUTER_ADDRESS = _oracleRouter;

        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
        _grantRoles(_oracle, ORACLE_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Retrieves the price of a specified asset
     * @param asset Address of the asset to price
     * @param inUSD Whether to return the price in USD (true) or ETH (false)
     * @return PriceReturnData Structure containing price, error status, and denomination
     */
    function getPrice(
        address asset,
        bool inUSD
    )
        external
        view
        virtual
        returns (ISharePriceOracle.PriceReturnData memory);

    /**
     * @notice Removes price feed support for an asset
     * @dev Must be implemented by child contracts
     * @param asset Address of the asset to remove
     */
    function removeAsset(address asset) external virtual;

    /**
     * @notice Updates the Oracle Router address
     * @param _oracleRouter New Oracle Router address
     */
    function updateOracleRouter(address _oracleRouter) external virtual {
        _checkAdminPermissions();
        ORACLE_ROUTER_ADDRESS = _oracleRouter;
    }

    /**
     * @notice Grants a role to an account
     * @param account Address to receive the role
     * @param role Role identifier to grant
     */
    function grantRole(address account, uint256 role) external {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();
        _checkAdminPermissions();
        _grantRoles(account, role);
        emit RoleGranted(account, role);
    }

    /**
     * @notice Revokes a role from an account
     * @param account Address to lose the role
     * @param role Role identifier to revoke
     */
    function revokeRole(address account, uint256 role) external {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();
        _checkAdminPermissions();
        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if a price would overflow uint240
     * @param price The price to check
     * @return bool True if price would overflow
     */
    function _checkOracleOverflow(uint256 price) internal pure returns (bool) {
        return price > type(uint240).max;
    }

    /**
     * @notice Validates admin role permissions
     */
    function _checkAdminPermissions() internal view {
        _checkRoles(ADMIN_ROLE);
    }

    /**
     * @notice Validates oracle role permissions
     */
    function _checkOraclePermissions() internal view {
        _checkRoles(ORACLE_ROLE);
    }
}
