-include .env

.PHONY: all test clean deploy-all configure-all send-from-all

# Helper commands
clean:
	forge clean

build:
	forge build

test:
	forge test

# Mainnet deployment commands
deploy-base:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		-vvv

deploy-optimism:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${OPTIMISTIC_API_KEY} \
		-vvv

deploy-arbitrum:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		-vvv

deploy-all: deploy-base deploy-optimism deploy-arbitrum

# LayerZero configuration commands
configure-base:
	forge script script/LzConfigure.s.sol:LzConfigure \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-optimism:
	forge script script/LzConfigure.s.sol:LzConfigure \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-arbitrum:
	forge script script/LzConfigure.s.sol:LzConfigure \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-all: configure-base configure-optimism configure-arbitrum

# Send share price commands
send-from-optimism-to-base: # Example: make send-from-optimism-to-base VAULT_ADDRESSES=0x123,0x456
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

send-from-base-to-optimism:
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

send-from-arbitrum-to-base:
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

# Testnet deployment commands
deploy-base-testnet:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${BASE_GOERLI_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${BASESCAN_API_KEY} \
		-vvv

deploy-optimism-testnet:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${OPTIMISM_GOERLI_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${OPTIMISTIC_API_KEY} \
		-vvv

deploy-arbitrum-testnet:
	forge script script/Deploy.s.sol:DeployScript \
		--rpc-url ${ARBITRUM_GOERLI_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		--verify \
		--etherscan-api-key ${ARBISCAN_API_KEY} \
		-vvv

deploy-all-testnet: deploy-base-testnet deploy-optimism-testnet deploy-arbitrum-testnet

# Simulation commands (for testing)
simulate-deploy:
	forge script script/Deploy.s.sol:DeployScript -vvv

simulate-configure:
	forge script script/LzConfigure.s.sol:LzConfigure -vvv

simulate-send:
	forge script script/SendSharePrices.s.sol:SendSharePrices -vvv

# Full deployment, configuration and test sequence
setup-all: deploy-all configure-all

setup-all-testnet: deploy-all-testnet configure-all

# Help target
help:
	@echo "Available targets:"
	@echo "  clean               - Clean build artifacts"
	@echo "  build              - Build the project"
	@echo "  test               - Run tests"
	@echo "  deploy-all         - Deploy to all mainnet chains"
	@echo "  configure-all      - Configure LayerZero on all chains"
	@echo "  setup-all          - Deploy and configure on all chains"
	@echo "  setup-all-testnet  - Deploy and configure on all testnets"
	@echo ""
	@echo "Send share prices between chains:"
	@echo "  send-from-optimism-to-base VAULT_ADDRESSES=0x123,0x456"
	@echo "  send-from-base-to-optimism VAULT_ADDRESSES=0x123,0x456"
	@echo "  send-from-arbitrum-to-base VAULT_ADDRESSES=0x123,0x456"
