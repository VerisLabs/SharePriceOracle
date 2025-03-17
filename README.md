# SharePriceOracle

A cross-chain oracle system for ERC4626 vault share prices, enabling secure and efficient price data transmission across different blockchain networks using LayerZero protocol.

## Overview

SharePriceOracle is a multi-adapter oracle system that supports multiple price feeds and fallback mechanisms for cross-chain ERC4626 vault share price routing. It combines functionality of price oracle adapters and router capabilities to provide unified price conversion across chains.

## Key Features

- Multi-chain support (Base, Optimism, Arbitrum)
- Multiple oracle adapter integration (Chainlink, API3, Pyth, Redstone)
- Fallback price feed mechanisms
- Cross-chain asset mapping
- Configurable price update heartbeats
- Sequencer uptime validation for L2 chains

## Architecture

### Core Components

1. **SharePriceOracle**: Main contract handling price routing and conversions
2. **MaxLzEndpoint**: LayerZero endpoint integration for cross-chain communication
3. **Oracle Adapters**: 
   - Chainlink
   - API3
   - Pyth
   - Redstone
   - Balancer
   - Curve

### Key Contracts

```solidity
SharePriceOracle.sol      // Main router contract
MaxLzEndpoint.sol         // LayerZero endpoint handler
adapters/
  Chainlink.sol          // Chainlink price feed adapter
  Api3.sol               // API3 price feed adapter
  Pyth.sol              // Pyth Network adapter
  Redstone.sol          // Redstone adapter
```

## Deployment

The deployment process is handled through several scripts:

1. Initial Deployment (`01_Deploy.s.sol`)
2. Base Chain Configuration (`02_ConfigureBase.s.sol`)
3. Peer Configuration (`03_ConfigurePeers.s.sol`)
4. Local Asset Addition (`04_AddLocalAssets.s.sol`)

### Prerequisites

```bash
export PRIVATE_KEY=your_private_key
export ROUTER_ADDRESS=deployed_router_address
```

### Deployment Steps

1. Deploy core contracts:
```bash
forge script script/01_Deploy.s.sol --broadcast
```

2. Configure Base chain:
```bash
forge script script/02_ConfigureBase.s.sol --broadcast
```

3. Configure peers on other chains:
```bash
forge script script/03_ConfigurePeers.s.sol --broadcast
```

4. Add local assets:
```bash
forge script script/04_AddLocalAssets.s.sol --broadcast
```

## Configuration

The system uses several JSON configuration files for price feeds:

- `balancerPriceFeeds.json`: Balancer pool configurations
- `curvePriceFeeds.json`: Curve pool configurations
- `priceFeedConfig.json`: General price feed configurations
- `pythPriceFeed.json`: Pyth Network specific configurations
- `redstonePriceFeed.json`: Redstone specific configurations

## Supported Networks

- Base (Chain ID: 8453)
- Optimism (Chain ID: 10)
- Arbitrum (Chain ID: 42161)
- Polygon (Chain ID: 137)

## Security

The contract implements several security features:

- Role-based access control
- Sequencer uptime validation for L2s
- Price feed heartbeat checks
- Multiple oracle fallback mechanisms

## Testing

Run the test suite:

```bash
forge test
```

## License

MIT
