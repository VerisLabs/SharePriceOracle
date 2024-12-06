// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {MessagingFee} from "./ILayerZeroEndpointV2.sol";

/**
 * @title VaultReport
 * @notice Structure containing vault share price information and metadata
 * @param sharePrice The current share price of the vault
 * @param lastUpdate Timestamp of the last update
 * @param chainId ID of the chain where the vault exists
 * @param rewardsDelegate Address to delegate rewards to
 * @param vaultAddress Address of the vault
 */
struct VaultReport {
    uint256 sharePrice;
    uint64 lastUpdate;
    uint32 chainId;
    address rewardsDelegate;
    address vaultAddress;
}

/**
 * @title ISharePriceOracle
 * @notice Interface for cross-chain ERC4626 vault share price oracle
 */
interface ISharePriceOracle {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event SharePriceUpdated(uint32 indexed srcChainId, address indexed vault, uint256 price, address rewardsDelegate);
    event LzEndpointUpdated(address oldEndpoint, address newEndpoint);
    event RoleGranted(address account, uint256 role);
    event RoleRevoked(address account, uint256 role);
    event HistoricalPriceCleaned(bytes32 indexed key, uint256 reportsRemoved);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAdminAddress();
    error ZeroAddress();
    error InvalidRole();
    error InvalidChainId(uint32 receivedChainId);
    error InvalidReporter();

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the chain ID of this oracle
    function chainId() external view returns (uint32);

    /// @notice Get the admin role identifier
    function ADMIN_ROLE() external view returns (uint256);

    /// @notice Get the endpoint role identifier
    function ENDPOINT_ROLE() external view returns (uint256);

    /// @notice Check if an account has a specific role
    function hasRole(address account, uint256 role) external view returns (bool);

    /// @notice Get all roles assigned to an account
    function getRoles(address account) external view returns (uint256);

    /// @notice Get current share prices for multiple vaults
    function getSharePrices(
        address[] calldata vaultAddresses,
        address rewardsDelegate
    ) external view returns (VaultReport[] memory);

    /// @notice Get stored share prices for multiple vaults
    function getStoredSharePrices(
        uint32 _srcChainId,
        address[] calldata _vaultAddresses
    ) external view returns (VaultReport[] memory);

    /// @notice Get latest share price for a specific vault
    function getLatestSharePrice(
        uint32 _srcChainId,
        address _vaultAddress
    ) external view returns (VaultReport memory);

    /// @notice Generate a unique key for a vault's price data
    function getPriceKey(
        uint32 _srcChainId,
        address _vault
    ) external pure returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update share prices from another chain
    function updateSharePrices(
        uint32 _srcChainId,
        VaultReport[] calldata _reports
    ) external;

    /// @notice Grant a role to an account
    function grantRole(address account, uint256 role) external;

    /// @notice Revoke a role from an account
    function revokeRole(address account, uint256 role) external;

    /// @notice Set the LayerZero endpoint address
    function setLzEndpoint(address _endpoint) external;

    /// @notice Remove old price reports for a given vault
    function cleanupOldReports(bytes32 key, uint256 maxAge) external;
}
