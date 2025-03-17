-include .env
export

.PHONY: all test clean deploy-all configure-lz-all configure-feeds-all configure-assets-all setup-all

# Helper commands
clean:
	forge clean

build:
	forge build --via-ir

test:
	forge test --via-ir

# Validation commands
validate-router-base:
	@forge script script/ValidateSharePriceOracle.sol:ValidateSharePriceOracle \
		--rpc-url ${BASE_RPC_URL} \
		--via-ir \
		-vvv

# Mainnet deployment commands
deploy-base:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--via-ir \
		-vvv

deploy-optimism:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${OPTIMISTIC_API_KEY} \
		--via-ir \
		-vvv

deploy-arbitrum:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--via-ir \
		-vvv

deploy-polygon:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${POLYGON_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${POLYGONSCAN_API_KEY} \
		--via-ir \
		-vvv

deploy-all: deploy-base deploy-optimism deploy-arbitrum deploy-polygon

# LayerZero configuration commands
configure-lz-base:
	@export TARGET_ENDPOINT_IDS=30110,30111,30109 && \
	forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-lz-optimism:
	@export TARGET_ENDPOINT_IDS=30184,30110,30109 && \
	forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-lz-arbitrum:
	@export TARGET_ENDPOINT_IDS=30184,30111,30109 && \
	forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-lz-polygon:
	@export TARGET_ENDPOINT_IDS=30184,30110,30111 && \
	forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint \
		--rpc-url ${POLYGON_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-lz-all: configure-lz-base configure-lz-optimism configure-lz-arbitrum configure-lz-polygon

# Price feed configuration commands
configure-feeds-base:
	@forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-feeds-optimism:
	@forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-feeds-arbitrum:
	@forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-feeds-all: configure-feeds-base configure-feeds-optimism configure-feeds-arbitrum

# Cross-chain asset mapping configuration commands
configure-assets-base:
	@forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-assets-optimism:
	@forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-assets-arbitrum:
	@forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

# Cross-chain asset category configuration commands
configure-categories-base:
	@forge script script/ConfigCrossChainCategories.sol:ConfigCrossChainCategories \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-categories-optimism:
	@forge script script/ConfigCrossChainCategories.sol:ConfigCrossChainCategories \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-categories-arbitrum:
	@forge script script/ConfigCrossChainCategories.sol:ConfigCrossChainCategories \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-assets-polygon:
	@forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets \
		--rpc-url ${POLYGON_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

configure-assets-all: configure-assets-base configure-assets-optimism configure-assets-arbitrum configure-assets-polygon

# Send share prices command
send-share-prices-base:
	@forge script script/SendSharePrices.sol:SendSharePrices \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

send-share-prices-optimism:
	@forge script script/SendSharePrices.sol:SendSharePrices \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

send-share-prices-arbitrum:
	@forge script script/SendSharePrices.sol:SendSharePrices \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

send-share-prices-polygon:
	@forge script script/SendSharePrices.sol:SendSharePrices \
		--rpc-url ${POLYGON_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--via-ir \
		-vvv

# Testnet deployment commands
deploy-base-testnet:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${BASE_SEPOLIA_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		--via-ir \
		-vvv

deploy-optimism-testnet:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${OPTIMISM_SEPOLIA_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${OPTIMISTIC_API_KEY} \
		--via-ir \
		-vvv

deploy-arbitrum-testnet:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle \
		--rpc-url ${ARBITRUM_SEPOLIA_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		--via-ir \
		-vvv

deploy-all-testnet: deploy-base-testnet deploy-optimism-testnet deploy-arbitrum-testnet

# Full deployment and configuration sequence
setup-all: deploy-all configure-lz-all configure-feeds-all configure-assets-all

setup-all-testnet: deploy-all-testnet

# Base-specific setup for vaults
setup-base-vaults: deploy-all configure-lz-all configure-feeds-base configure-assets-all
	@echo "Base vault setup complete. Deployed to all chains, configured LayerZero on all chains,"
	@echo "configured price feeds on Base, and configured cross-chain assets on all chains."

# Help target
help:
	@echo "Available targets:"
	@echo "  clean                  - Clean build artifacts"
	@echo "  build                  - Build the project"
	@echo "  test                   - Run tests"
	@echo ""
	@echo "Deployment commands:"
	@echo "  deploy-base            - Deploy to Base mainnet"
	@echo "  deploy-optimism        - Deploy to Optimism mainnet"
	@echo "  deploy-arbitrum        - Deploy to Arbitrum mainnet"
	@echo "  deploy-polygon         - Deploy to Polygon mainnet"
	@echo "  deploy-all             - Deploy to all mainnet chains"
	@echo ""
	@echo "Configuration commands:"
	@echo "  configure-lz-all       - Configure LayerZero on all chains"
	@echo "  configure-feeds-all    - Configure price feeds on all chains"
	@echo "  configure-assets-all   - Configure cross-chain assets on all chains"
	@echo ""
	@echo "Complete setup:"
	@echo "  setup-all              - Deploy and configure everything on all chains"
	@echo "  setup-base-vaults      - Setup for Base-only vaults (deploy to all chains, configure feeds on Base only)"
	@echo ""
	@echo "Testnet commands:"
	@echo "  deploy-all-testnet     - Deploy to all testnet chains"
	@echo "  setup-all-testnet      - Deploy and configure on all testnets"
	@echo ""
	@echo "Simulation commands:"
	@echo "  simulate-deploy        - Simulate deployment without broadcasting"
	@echo "  simulate-configure-lz  - Simulate LZ configuration without broadcasting"
	@echo "  simulate-configure-feeds - Simulate price feed configuration without broadcasting"
	@echo "  simulate-configure-assets - Simulate cross-chain asset configuration without broadcasting"
	@echo ""
	@echo "Send share prices between chains:"
	@echo "  send-share-prices-base"
	@echo "  send-share-prices-optimism"
	@echo "  send-share-prices-arbitrum"
	@echo "  send-share-prices-polygon"

# Simulation commands (for testing)
simulate-deploy:
	@forge script script/DeploySharePriceOracle.sol:DeploySharePriceOracle --via-ir -vvv

simulate-configure-lz:
	@mkdir -p mock_deployments
	@echo '{"router": "0x1000000000000000000000000000000000000000","endpoint": "0x2000000000000000000000000000000000000000","chainlinkAdapter": "0x3000000000000000000000000000000000000000","api3Adapter": "0x4000000000000000000000000000000000000000","admin": "0x5000000000000000000000000000000000000000","chainId": 31337,"lzEndpointId": 31337,"lzEndpoint": "0x6000000000000000000000000000000000000000","network": "Anvil"}' > mock_deployments/Anvil_31337.json
	@echo '{"router": "0x1100000000000000000000000000000000000000","endpoint": "0x2100000000000000000000000000000000000000","chainlinkAdapter": "0x3100000000000000000000000000000000000000","api3Adapter": "0x4100000000000000000000000000000000000000","admin": "0x5100000000000000000000000000000000000000","chainId": 42161,"lzEndpointId": 30110,"lzEndpoint": "0x6100000000000000000000000000000000000000","network": "Arbitrum"}' > mock_deployments/Arbitrum_42161.json
	@echo '{"router": "0x1200000000000000000000000000000000000000","endpoint": "0x2200000000000000000000000000000000000000","chainlinkAdapter": "0x3200000000000000000000000000000000000000","api3Adapter": "0x4200000000000000000000000000000000000000","admin": "0x5200000000000000000000000000000000000000","chainId": 10,"lzEndpointId": 30111,"lzEndpoint": "0x6200000000000000000000000000000000000000","network": "Optimism"}' > mock_deployments/Optimism_10.json
	@echo '{"router": "0x1300000000000000000000000000000000000000","endpoint": "0x2300000000000000000000000000000000000000","chainlinkAdapter": "0x3300000000000000000000000000000000000000","api3Adapter": "0x4300000000000000000000000000000000000000","admin": "0x5300000000000000000000000000000000000000","chainId": 137,"lzEndpointId": 30109,"lzEndpoint": "0x6300000000000000000000000000000000000000","network": "Polygon"}' > mock_deployments/Polygon_137.json
	@export TARGET_ENDPOINT_IDS=30110,30111,30109 && \
	forge script script/ConfigLzEndpoint.sol:ConfigLzEndpoint --via-ir -vvv

simulate-configure-feeds:
	@forge script script/ConfigPriceFeeds.sol:ConfigPriceFeeds --via-ir -vvv

simulate-configure-assets:
	@forge script script/ConfigCrossChainAssets.sol:ConfigCrossChainAssets --via-ir -vvv
