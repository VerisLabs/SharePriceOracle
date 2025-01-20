-include .env

.PHONY: all test clean deploy-all configure-all

# Helper commands
clean:
	forge clean

build:
	forge build

test:
	forge test

# Deployment commands
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
	forge script script/ConfigLzEndpoint.s.sol:ConfigLzEndpoint \
		--rpc-url ${BASE_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-optimism:
	forge script script/ConfigLzEndpoint.s.sol:ConfigLzEndpoint \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-arbitrum:
	forge script script/ConfigLzEndpoint.s.sol:ConfigLzEndpoint \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--private-key ${PRIVATE_KEY} \
		--broadcast \
		-vvv

configure-all: configure-base configure-optimism configure-arbitrum

# Deploy and configure testnet commands
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

# Simulate commands (for testing deployments and configurations)
simulate-deploy:
	forge script script/Deploy.s.sol:DeployScript -vvv

simulate-configure:
	forge script script/ConfigLzEndpoint.s.sol:ConfigLzEndpoint -vvv

# Send commands
send-from-optimism:
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${OPTIMISM_RPC_URL} \
		--broadcast \
		-vvv

send-from-base:
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${BASE_RPC_URL} \
		--broadcast \
		-vvv

send-from-arbitrum:
	forge script script/SendSharePrices.s.sol:SendSharePrices \
		--rpc-url ${ARBITRUM_RPC_URL} \
		--broadcast \
		-vvv
