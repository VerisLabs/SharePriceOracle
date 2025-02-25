# SharePriceOracle

A multi-adapter oracle system for cross-chain ERC4626 vault share prices with robust fallback mechanisms.

## Overview

SharePriceOracle is a decentralized oracle system that enables accessing and sharing ERC4626 vault share prices across different blockchain networks. It provides a resilient architecture with multiple price feed adapters and cross-chain communication capabilities via LayerZero.

### Key Features

- **Multi-Adapter Architecture**: Supports multiple oracle providers (Chainlink, API3) with fallback mechanisms
- **Cross-Chain Communication**: Secure vault share price updates between different blockchain networks
- **Asset Category Optimization**: Special handling for different asset types (BTC-like, ETH-like, stablecoins)
- **Fallback Mechanism**: Graceful degradation when primary price sources are unavailable
- **Price Conversion**: Convert prices between different assets and denominations (USD, ETH)
- **Role-Based Access Control**: Granular security permissions

## System Architecture

### Core Components

#### SharePriceRouter
The main contract that orchestrates the oracle adapters and provides unified price conversion:
- Manages multiple oracle adapters with priority-based failover
- Handles price conversion between different assets
- Stores historical price data
- Cross-chain share price mapping and updates
- Asset categorization for optimized conversion

#### Oracle Adapters
Modular price feed providers that fetch and normalize price data:

- **BaseOracleAdapter**: Abstract base contract for all adapters
- **ChainlinkAdapter**: Integration with Chainlink price feeds
- **Api3Adapter**: Integration with API3 price feeds

#### MaxLzEndpoint
Manages cross-chain communication via LayerZero protocol:
- Secure message passing between chains
- Peer verification and validation
- Fee estimation and payment
- Request-response pattern support

### Cross-Chain Flow

1. **Source Chain**:
   - Share prices are collected from local vaults via `getSharePrices`
   - Encoded as `VaultReport` structures
   - Sent via LayerZero to destination chain

2. **Destination Chain**:
   - Message is received and verified by `MaxLzEndpoint`
   - Share prices are extracted and passed to `SharePriceRouter`
   - Prices are stored with chain ID mapping for later use

3. **Price Access**:
   - Applications can query share prices via `getLatestSharePrice`
   - The system attempts multiple fallback strategies:
     1. Direct price calculation through oracles
     2. Cross-chain price data
     3. Stored price data
     4. Destination vault's own share price as final fallback

### Security Model

- **Role-Based Access Control**:
  - `ADMIN_ROLE`: Configuration and management
  - `UPDATER_ROLE`: Price update operations
  - `ENDPOINT_ROLE`: LayerZero endpoint operations

- **Price Validation**:
  - Staleness checks (24-hour threshold)
  - Min/Max bounds for prices
  - Decimal overflow protection
  - Sequencer health validation for L2 chains

- **Cross-Chain Security**:
  - Peer validation for LayerZero endpoints
  - Message deduplication
  - Chain ID verification

## Prerequisites

- [Foundry](https://getfoundry.sh/)
- Make
- Solidity ^0.8.17

## Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd SharePriceOracle
```

2. Install dependencies:
```bash
forge install
```

3. Copy the example environment file and fill in your values:
```bash
cp env.example .env
```

## Configuration

Key environment variables in `.env`:

```env
# Deployment private key
PRIVATE_KEY=

# Admin address
ADMIN_ADDRESS=

# RPC URLs
BASE_RPC_URL=
OPTIMISM_RPC_URL=
ARBITRUM_RPC_URL=

# Etherscan API Keys for verification
ETHERSCAN_API_KEY=
BASESCAN_API_KEY=
ARBISCAN_API_KEY=
OPTIMISTIC_API_KEY=

# LayerZero configuration
LZ_GAS_LIMIT=500000
LZ_NATIVE_VALUE=200000

# Chain-specific token addresses
BASE_USDC=
BASE_WETH=
BASE_WBTC=
OPTIMISM_USDC=
OPTIMISM_WETH=
OPTIMISM_WBTC=
ARBITRUM_USDC=
ARBITRUM_WETH=
ARBITRUM_WBTC=

# Chainlink feed addresses
BASE_ETH_USD_FEED=
OPTIMISM_ETH_USD_FEED=
ARBITRUM_ETH_USD_FEED=
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

### Configure Oracle Adapters
```bash
# Add Chainlink adapter for asset pricing
make add-chainlink-adapter CHAIN=base \
  ASSET=0x123 \
  AGGREGATOR=0x456 \
  HEARTBEAT=3600 \
  IN_USD=true

# Add API3 adapter for asset pricing
make add-api3-adapter CHAIN=optimism \
  ASSET=0x789 \
  TICKER="BTC/USD" \
  PROXY_FEED=0xabc \
  HEARTBEAT=7200 \
  IN_USD=true
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

### Cross-Chain Share Price Operations
```bash
# Send share prices from one chain to another
make send-share-prices CHAIN=optimism \
  DST_CHAIN=8453 \
  VAULT_ADDRESSES=0x123,0x456 \
  REWARDS_DELEGATE=0x789

# Request share prices from another chain
make request-share-prices CHAIN=base \
  DST_CHAIN=10 \
  VAULT_ADDRESSES=0x123,0x456 \
  REWARDS_DELEGATE=0x789
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

struct PriceReturnData {
    uint240 price;       // Price normalized to WAD (1e18)
    bool hadError;       // Error flag
    bool inUSD;          // Price denomination
}

enum AssetCategory {
    UNKNOWN,
    BTC_LIKE,  // WBTC, BTCb, TBTC, etc.
    ETH_LIKE,  // ETH, stETH, rsETH, etc.
    STABLE     // USDC, USDT, DAI, etc.
}
```

### System Limitations

- Dependence on external oracle quality and uptime
- LayerZero gas costs for cross-chain operations
- 24-hour price staleness threshold for all assets
- Maximum 100 reports per cross-chain message
- Price precision limited to uint240 (to fit in storage)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
