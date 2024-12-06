// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {IERC4626} from "./interfaces/IERC4626.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {ISharePriceOracle, VaultReport} from "./interfaces/ISharePriceOracle.sol";

contract SharePriceOracle is ISharePriceOracle, OwnableRoles {
    ////////////////////////////////////////////////////////////////
    ///                        CONSTANTS                           ///
    ////////////////////////////////////////////////////////////////

    /// @notice Role identifier for admin capabilities
    uint256 public constant ADMIN_ROLE = _ROLE_0;

    /// @notice Role identifier for LayerZero endpoint
    uint256 public constant ENDPOINT_ROLE = _ROLE_1;

    ////////////////////////////////////////////////////////////////
    ///                      STATE VARIABLES                       ///
    ////////////////////////////////////////////////////////////////
    /// @notice Chain ID this oracle is deployed on
    uint32 public immutable override chainId;

    /// @notice LayerZero endpoint address
    address private lzEndpoint;

    /// @notice Mapping from price key to array of vault reports
    /// @dev Key is keccak256(abi.encodePacked(srcChainId, vaultAddress))
    mapping(bytes32 => VaultReport[]) public sharePrices;

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

    ////////////////////////////////////////////////////////////////
    ///                     CONSTRUCTOR                           ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Initializes the oracle with chain ID and admin address
     * @param _chainId The chain ID this oracle is deployed on
     * @param _admin Address of the initial admin
     */
    constructor(uint32 _chainId, address _admin) {
        if (_admin == address(0)) revert InvalidAdminAddress();
        chainId = _chainId;
        _initializeOwner(_admin);
        _grantRoles(_admin, ADMIN_ROLE);
    }

    ////////////////////////////////////////////////////////////////
    ///                    ADMIN FUNCTIONS                        ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Sets the LayerZero endpoint address
     * @param _endpoint New endpoint address
     */
    function setLzEndpoint(address _endpoint) external onlyAdmin {
        if (_endpoint == address(0)) revert ZeroAddress();
        address oldEndpoint = lzEndpoint;
        lzEndpoint = _endpoint;
        _grantRoles(_endpoint, ENDPOINT_ROLE);
        emit LzEndpointUpdated(oldEndpoint, _endpoint);
        emit RoleGranted(_endpoint, ENDPOINT_ROLE);
    }
    
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
    function revokeRole(address account, uint256 role) external override onlyAdmin {
        if (account == address(0)) revert ZeroAddress();
        if (role == 0) revert InvalidRole();

        _removeRoles(account, role);
        emit RoleRevoked(account, role);
    }
    
    /**
     * @notice Removes old price reports for a given vault
     * @param key The price key to clean up
     * @param maxAge Maximum age of reports to keep (in seconds)
     */
    function cleanupOldReports(bytes32 key, uint256 maxAge) external override onlyAdmin {
        VaultReport[] storage reports = sharePrices[key];
        uint256 originalLength = reports.length;
        uint256 i = 0;

        while (i < reports.length) {
            if (block.timestamp - reports[i].lastUpdate > maxAge) {
                reports[i] = reports[reports.length - 1];
                reports.pop();
            } else {
                i++;
            }
        }

        emit HistoricalPriceCleaned(key, originalLength - reports.length);
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL FUNCTIONS                       ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Updates share prices from another chain
     * @param _srcChainId Source chain ID
     * @param reports Array of vault reports to update
     */
    function updateSharePrices(
        uint32 _srcChainId,
        VaultReport[] calldata reports
    ) external override onlyEndpoint {
        if (_srcChainId == chainId) revert InvalidChainId(_srcChainId);

        uint256 len = reports.length;
        bytes32 key;

        unchecked {
            for (uint256 i; i < len; ++i) {
                VaultReport calldata report = reports[i];
                if (report.chainId != _srcChainId) {
                    revert InvalidChainId(report.chainId);
                }
                key = getPriceKey(_srcChainId, report.vaultAddress);
                sharePrices[key].push(report);

                emit SharePriceUpdated(
                    _srcChainId,
                    report.vaultAddress,
                    report.sharePrice,
                    report.rewardsDelegate
                );
            }
        }
    }

    ////////////////////////////////////////////////////////////////
    ///                 EXTERNAL VIEW FUNCTIONS                   ///
    ////////////////////////////////////////////////////////////////
    /**
     * @notice Gets current share prices for multiple vaults
     * @param vaultAddresses Array of vault addresses
     * @param rewardsDelegate Address to delegate rewards to
     * @return VaultReport[] Array of vault reports
     */
    function getSharePrices(
        address[] calldata vaultAddresses,
        address rewardsDelegate
    ) external view override returns (VaultReport[] memory) {
        uint256 len = vaultAddresses.length;
        VaultReport[] memory reports = new VaultReport[](len);
        uint64 timestamp = uint64(block.timestamp);

        unchecked {
            for (uint256 i; i < len; ++i) {
                address vaultAddress = vaultAddresses[i];
                IERC4626 vault = IERC4626(vaultAddress);
                uint256 decimals = vault.decimals();
                uint256 sharePrice = vault.convertToAssets(10 ** decimals);

                reports[i].lastUpdate = timestamp;
                reports[i].chainId = chainId;
                reports[i].vaultAddress = vaultAddress;
                reports[i].sharePrice = sharePrice;
                reports[i].rewardsDelegate = rewardsDelegate;
            }
        }
        return reports;
    }

    /**
     * @notice Gets stored share prices for multiple vaults
     * @param _srcChainId Source chain ID
     * @param _vaultAddresses Array of vault addresses
     * @return VaultReport[] Array of vault reports
     */
    function getStoredSharePrices(
        uint32 _srcChainId,
        address[] calldata _vaultAddresses
    ) external view override returns (VaultReport[] memory) {
        uint256 len = _vaultAddresses.length;
        VaultReport[] memory reports = new VaultReport[](len * 10); // remove hardcoded
        uint256 reportIndex = 0;

        unchecked {
            for (uint256 i; i < len; ++i) {
                bytes32 key = getPriceKey(_srcChainId, _vaultAddresses[i]);
                VaultReport[] storage vaultReports = sharePrices[key];
                uint256 vaultReportsLen = vaultReports.length;
                for (uint256 j; j < vaultReportsLen; ++j) {
                    reports[reportIndex++] = vaultReports[j];
                }
            }
        }

        return reports;
    }
    
    /**
     * @notice Gets latest share price for a specific vault
     * @param _srcChainId Source chain ID
     * @param _vaultAddress Vault address
     * @return VaultReport The latest vault report
     */
    function getLatestSharePrice(
        uint32 _srcChainId,
        address _vaultAddress
    ) external view override returns (VaultReport memory) {
        bytes32 key = getPriceKey(_srcChainId, _vaultAddress);
        VaultReport[] storage vaultReports = sharePrices[key];
        return vaultReports[vaultReports.length - 1];
    }
    
    /**
     * @notice Generates a unique key for a vault's price data
     * @param _srcChainId Source chain ID
     * @param _vault Vault address
     * @return bytes32 The generated key
     */
    function getPriceKey(
        uint32 _srcChainId,
        address _vault
    ) public pure override returns (bytes32) {
        return keccak256(abi.encodePacked(_srcChainId, _vault));
    }
    
    /**
     * @notice Checks if an account has a specific role
     * @param account Address to check
     * @param role Role to check for
     * @return bool True if account has the role
     */
    function hasRole(address account, uint256 role) public view override returns (bool) {
        return hasAnyRole(account, role);
    }
    
    /**
     * @notice Gets all roles assigned to an account
     * @param account Address to check
     * @return uint256 Bitmap of assigned roles
     */
    function getRoles(address account) external view override returns (uint256) {
        return rolesOf(account);
    }
}
