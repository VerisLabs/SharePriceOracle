# SharePriceOracle

A cross-chain oracle for tracking and sharing ERC4626 vault share prices, built with LayerZero for secure cross-chain communication.

## Overview

SharePriceOracle enables protocols to access and update ERC4626 vault share prices across different chains. It provides a reliable way to maintain share price information for cross-chain vault operations, with features for price updates, historical data management, and role-based access control.

## Features

- Cross-chain share price updates via LayerZero
- Support for ERC4626 vault share price tracking
- Historical price data storage and management
- Role-based access control system
- Reward delegation support
- Efficient data cleanup mechanisms

## Installation

```bash
forge install
```

## Usage

### Deploy the Oracle

```solidity
uint32 chainId = 1; // Ethereum Mainnet
address admin = 0x...; // Admin address
SharePriceOracle oracle = new SharePriceOracle(chainId, admin);
```

### Configure LayerZero

```solidity
// Set LayerZero endpoint
oracle.setLzEndpoint(lzEndpointAddress);
```

### Update Share Prices

```solidity
// Create vault reports
VaultReport[] memory reports = new VaultReport[](1);
reports[0] = VaultReport({
    sharePrice: 1e18,
    lastUpdate: uint64(block.timestamp),
    chainId: sourceChainId,
    rewardsDelegate: delegateAddress,
    vaultAddress: vaultAddress
});

// Update prices onlyEndpoint
oracle.updateSharePrices(sourceChainId, reports);
```

### Query Share Prices

```solidity
// Get current share prices
address[] memory vaults = new address[](1);
vaults[0] = vaultAddress;
VaultReport[] memory prices = oracle.getSharePrices(vaults, delegateAddress);

// Get latest stored price
VaultReport memory latest = oracle.getLastestSharePrice(sourceChainId, vaultAddress);
```

## Architecture

### Core Components

- `SharePriceOracle.sol`: Main oracle contract
- `ISharePriceOracle.sol`: Interface defining oracle functionality
- `VaultReport`: Struct containing share price data and metadata

### Key Mappings

```solidity
mapping(bytes32 => VaultReport[]) public sharePrices;
```
Stores price history for each vault, keyed by a combination of chain ID and vault address.

## Security

### Roles

- `ADMIN_ROLE`: Can manage oracle configuration and roles
- `ENDPOINT_ROLE`: Assigned to LayerZero endpoint for cross-chain updates

### Access Control

- Role-based permissions for administrative functions
- Chain ID validation for cross-chain updates
- Address validation for configuration changes

## Gas Optimization

The contract implements several gas optimization techniques:
- Using unchecked blocks for safe arithmetic
- Efficient storage patterns
- Optional historical data cleanup

## Events

```solidity
event SharePriceUpdated(uint32 indexed srcChainId, address indexed vault, uint256 price, address rewardsDelegate);
event LzEndpointUpdated(address oldEndpoint, address newEndpoint);
event RoleGranted(address account, uint256 role);
event RoleRevoked(address account, uint256 role);
event HistoricalPriceCleaned(bytes32 indexed key, uint256 reportsRemoved);
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under MIT.

## Contact

For questions and support, please open an issue in the repository.
