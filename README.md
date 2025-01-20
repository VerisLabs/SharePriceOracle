# Cross-Chain ERC4626 Share Price Oracle

A decentralized oracle system for sharing ERC4626 vault share prices across different L2 networks using LayerZero.

## Overview

This project implements a cross-chain oracle system for ERC4626 vault share prices. It enables vaults on different chains to access share price information from vaults on other networks, facilitating cross-chain vault strategies and integrations.

### Key Features

- Cross-chain ERC4626 vault share price oracle
- Price conversion using Chainlink price feeds
- Support for both USD and ETH denominated price feeds
- LayerZero integration for secure cross-chain messaging
- Role-based access control for security
- Configurable staleness checks for price data

## System Architecture

### Core Components

#### SharePriceOracle
The main oracle contract that manages vault share prices and conversions.
- Share price updates from remote chains
- Asset price conversion using Chainlink feeds
- Support for both USD and ETH denominated feeds
- Price staleness checks
- Role-based access control

#### MaxLzEndpoint
Handles cross-chain communication through LayerZero protocol.
- Message sending and receiving
- Fee calculation and payment
- Peer verification
- Configurable gas limits

#### Supporting Libraries
- **ChainlinkLib**: Safe price feed interaction with validation
- **VaultLib**: ERC4626 vault interaction and share price calculations
- **PriceConversionLib**: Asset price conversion with decimal handling
- **MsgCodec**: Message encoding/decoding for cross-chain communication

### Cross-Chain Flow
1. Source Chain:
   - Get vault share prices
   - Encode message
   - Calculate LayerZero fees
   - Send message
2. Destination Chain:
   - Receive message
   - Verify sender
   - Decode message
   - Update share prices

### Security Model
- Role-based access control (ADMIN_ROLE, ENDPOINT_ROLE)
- Price feed validation and staleness checks
- Safe math operations
- LayerZero security integration
- Peer verification system

## Prerequisites

- [Foundry](https://getfoundry.sh/)
- Make
- Solidity ^0.8.19

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd <repository-name>
```

2. Install dependencies:
```bash
forge install
```

3. Copy the example environment file and fill in your values:
```bash
cp .env.example .env
```

## Configuration

Create a `.env` file with the following variables:

```env
# Deployment private key
PRIVATE_KEY=

# Admin address (optional, will use private key address if not set)
ADMIN_ADDRESS=

# RPC URLs
BASE_RPC_URL=
OPTIMISM_RPC_URL=
ARBITRUM_RPC_URL=

# Flags
SETUP_PERMISSIONS=true

# Etherscan API Keys for verification
ETHERSCAN_API_KEY=
BASESCAN_API_KEY=
ARBISCAN_API_KEY=
OPTIMISTIC_API_KEY=

# Comma-separated list of target chain IDs for LZ configuration
# Example: For Optimism configuring peers with Base and Arbitrum
TARGET_CHAIN_IDS=8453,42161

# Destination chain ID
DST_CHAIN_ID=8453  # Example: Base chain ID

# LayerZero configuration
LZ_GAS_LIMIT=500000
LZ_NATIVE_VALUE=200000

# Rewards delegate address
REWARDS_DELEGATE=

# Vault addresses (comma-separated)
VAULT_ADDRESSES=
```

## Development and Deployment

### Building
```bash
make build
```

### Testing
```bash
# Run all tests
make test

# Run with detailed output
forge test -vvv
```

### Deployment
```bash
# Deploy to all networks
make deploy-all

# Or deploy to specific networks
make deploy-base
make deploy-optimism
make deploy-arbitrum
```

### LayerZero Configuration
```bash
# Configure all networks
make configure-all

# Or configure specific networks
make configure-base
make configure-optimism
make configure-arbitrum
```

### Sending Share Prices
```bash
# From Optimism to Base
make send-from-optimism-to-base VAULT_ADDRESSES=0x123,0x456

# From Base to Optimism
make send-from-base-to-optimism VAULT_ADDRESSES=0x123,0x456
```

## Smart Contract Architecture

### Key Data Structures

```solidity
struct VaultReport {
    uint256 sharePrice;
    uint64 lastUpdate;
    uint32 chainId;
    address rewardsDelegate;
    address vaultAddress;
    address asset;
    uint256 assetDecimals;
}

struct ChainlinkResponse {
    uint256 price;
    uint8 decimals;
    uint256 timestamp;
    uint80 roundId;
    uint80 answeredInRound;
}
```

### System Limitations

- Depends on Chainlink price feed availability
- Subject to LayerZero gas costs
- Price staleness depends on update frequency
- Maximum number of reports per transaction

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
