// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { MessagingFee } from "./ILayerZeroEndpointV2.sol";

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
    address asset;
    uint256 assetDecimals;
}

/**
 * @title ChainlinkResponse
 * @notice Structure containing Chainlink price feed response data
 * @param price The price of the asset
 * @param decimals The number of decimals in the price
 * @param timestamp The timestamp of the price data
 * @param roundId The round ID of the price data
 * @param answeredInRound The round ID of the round in which the price data was reported
 */
struct ChainlinkResponse {
    uint256 price;
    uint8 decimals;
    uint256 timestamp;
    uint80 roundId;
    uint80 answeredInRound;
}

enum PriceDenomination {
    USD,
    ETH
}

struct PriceFeedInfo {
    address feed;
    PriceDenomination denomination;
    uint32 heartbeat;
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
    event PriceFeedSet(uint32 indexed chainId, address indexed asset, address priceFeed);

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
    )
        external
        view
        returns (VaultReport[] memory);

    /// @notice Get latest share price for a specific vault
    function getLatestSharePriceReport(
        uint32 _srcChainId,
        address _vaultAddress
    )
        external
        view
        returns (VaultReport memory);

    /// @notice Get latest share price for a specific vault / asset pair
    function getLatestSharePrice(
        uint32 _srcChainId,
        address _vaultAddress,
        address _dstAsset
    )
        external
        view
        returns (uint256 price, uint64 timestamp);

    /// @notice Generate a unique key for a vault's price data
    function getPriceKey(uint32 _srcChainId, address _vault) external pure returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Update share prices from another chain
    function updateSharePrices(uint32 _srcChainId, VaultReport[] calldata _reports) external;

    /// @notice Grant a role to an account
    function grantRole(address account, uint256 role) external;

    /// @notice Revoke a role from an account
    function revokeRole(address account, uint256 role) external;

    /// @notice Set the LayerZero endpoint address
    function setLzEndpoint(address _endpoint) external;
}
