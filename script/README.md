# SharePriceOracle Deployment Scripts

This directory contains scripts for deploying and configuring the SharePriceRouter system.

## Overview

The SharePriceRouter system consists of:
- `SharePriceRouter`: Main contract for price conversion and cross-chain communication
- `MaxLzEndpoint`: LayerZero integration for cross-chain messaging
- `ChainlinkAdapter`: Adapter for Chainlink price feeds
- `Api3Adapter`: Adapter for API3 price feeds

## Deployment Process

### 1. Deploy Contracts

```bash
# Set your private key and admin address
export PRIVATE_KEY=your_private_key
export ADMIN_ADDRESS=your_admin_address
export ORACLE_ADDRESS=your_oracle_address
export SETUP_PERMISSIONS=true

# Deploy on Base
forge script script/DeploySharePriceRouter.sol:DeploySharePriceRouter --rpc-url base --broadcast --verify

# Deploy on Arbitrum
forge script script/DeploySharePriceRouter.sol:DeploySharePriceRouter --rpc-url arbitrum --broadcast --verify

# Deploy on Optimism
forge script script/DeploySharePriceRouter.sol:DeploySharePriceRouter --rpc-url optimism --broadcast --verify

# Deploy on Polygon
forge script script/DeploySharePriceRouter.sol:DeploySharePriceRouter --rpc-url polygon --broadcast --verify
```

### 2. Configure LayerZero Endpoints

After deploying on all chains, configure the LayerZero endpoints to communicate with each other:

```bash
# Configure Base to communicate with Arbitrum, Optimism, and Polygon
export TARGET_ENDPOINT_IDS=30110,30111,30109
forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint --rpc-url base --broadcast

# Configure Arbitrum to communicate with Base, Optimism, and Polygon
export TARGET_ENDPOINT_IDS=30184,30111,30109
forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint --rpc-url arbitrum --broadcast

# Configure Optimism to communicate with Base, Arbitrum, and Polygon
export TARGET_ENDPOINT_IDS=30184,30110,30109
forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint --rpc-url optimism --broadcast

# Configure Polygon to communicate with Base, Arbitrum, and Optimism
export TARGET_ENDPOINT_IDS=30184,30110,30111
forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint --rpc-url polygon --broadcast
```

### 3. Configure Price Feeds

Configure the price feeds for each chain:

```bash
# Configure price feeds on Base
forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds --rpc-url base --broadcast

# Configure price feeds on Arbitrum
forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds --rpc-url arbitrum --broadcast

# Configure price feeds on Optimism
forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds --rpc-url optimism --broadcast

# Configure price feeds on Polygon
forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds --rpc-url polygon --broadcast
```

### 4. Configure Cross-Chain Asset Mappings

Configure cross-chain asset mappings:

```bash
# Configure cross-chain asset mappings on Base
forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets --rpc-url base --broadcast

# Configure cross-chain asset mappings on Arbitrum
forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets --rpc-url arbitrum --broadcast

# Configure cross-chain asset mappings on Optimism
forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets --rpc-url optimism --broadcast

# Configure cross-chain asset mappings on Polygon
forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets --rpc-url polygon --broadcast
```

## Configuration Files

- `script/config/priceFeedConfig.json`: Contains price feed configurations for each chain
- `script/libs/ChainConfig.sol`: Contains chain-specific configurations

## Deployment Files

After deployment, JSON files will be created in the `deployments/` directory with the following naming convention:
- `{network_name}_{chain_id}.json`

For example:
- `Base_8453.json`
- `Arbitrum_42161.json`
- `Optimism_10.json`
- `Polygon_137.json`

These files contain the addresses of the deployed contracts and are used by the configuration scripts. 