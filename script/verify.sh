#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Check required environment variables
if [ -z "$BASESCAN_API_KEY" ]; then
    echo -e "${RED}Error: BASESCAN_API_KEY environment variable is not set${NC}"
    exit 1
fi

if [ -z "$OPTIMISTIC_API_KEY" ]; then
    echo -e "${RED}Error: OPTIMISTIC_API_KEY environment variable is not set${NC}"
    exit 1
fi

if [ -z "$ARBISCAN_API_KEY" ]; then
    echo -e "${RED}Error: ARBISCAN_API_KEY environment variable is not set${NC}"
    exit 1
fi

echo "Starting contract verification..."

# Base Chain
echo -e "${GREEN}Verifying Base chain contracts...${NC}"

echo "Verifying SharePriceRouter..."
forge verify-contract 0x3e3d846273bd7b8ae8be33c06a956731616310e8 SharePriceRouter --chain base \
    --constructor-args $(cast abi-encode "constructor(address)" "0x429796dac057e7c15724196367007f1e9cff82f9") \
    --etherscan-api-key $BASESCAN_API_KEY \
    --watch

echo "Verifying MaxLzEndpoint..."
forge verify-contract 0x8fca5b55f28d642268e77ed04bb3d4ab8879a05c MaxLzEndpoint --chain base \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" "0x429796dac057e7c15724196367007f1e9cff82f9" "0x1a44076050125825900e736c501f859c50fE728c" "0x3e3d846273bd7b8ae8be33c06a956731616310e8") \
    --etherscan-api-key $BASESCAN_API_KEY \
    --watch

echo "Verifying ChainlinkAdapter..."
forge verify-contract 0x98c0a4d434d0fbf8b7506671604ac99f61dc3fb0 ChainlinkAdapter --chain base \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" "0x429796dac057e7c15724196367007f1e9cff82f9" "0x3e3d846273bd7b8ae8be33c06a956731616310e8" "0x3e3d846273bd7b8ae8be33c06a956731616310e8") \
    --etherscan-api-key $BASESCAN_API_KEY \
    --watch

echo "Verifying Api3Adapter..."
forge verify-contract 0x55481007c43e4950c8b640a31b994bf5733a87a1 Api3Adapter --chain base \
    --constructor-args $(cast abi-encode "constructor(address,address,address,address)" "0x429796dac057e7c15724196367007f1e9cff82f9" "0x3e3d846273bd7b8ae8be33c06a956731616310e8" "0x3e3d846273bd7b8ae8be33c06a956731616310e8" "0x4200000000000000000000000000000000000006") \
    --etherscan-api-key $BASESCAN_API_KEY \
    --watch

# Optimism Chain
echo -e "${GREEN}Verifying Optimism chain contracts...${NC}"

echo "Verifying SharePriceRouter..."
forge verify-contract 0x650308728a1cd70bbcdc1b76c389e83bb52f6936 SharePriceRouter --chain optimism \
    --constructor-args $(cast abi-encode "constructor(address)" "0x429796dac057e7c15724196367007f1e9cff82f9") \
    --etherscan-api-key $OPTIMISTIC_API_KEY \
    --watch

echo "Verifying MaxLzEndpoint..."
forge verify-contract 0x61495da28b18dee8b22f040ae115d963cb1f5897 MaxLzEndpoint --chain optimism \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" "0x429796dac057e7c15724196367007f1e9cff82f9" "0x1a44076050125825900e736c501f859c50fE728c" "0x650308728a1cd70bbcdc1b76c389e83bb52f6936") \
    --etherscan-api-key $OPTIMISTIC_API_KEY \
    --watch

# Arbitrum Chain
echo -e "${GREEN}Verifying Arbitrum chain contracts...${NC}"

echo "Verifying SharePriceRouter..."
forge verify-contract 0xe6d2ac67f3fcb23c6e0babcd2b1c490a1e49cbfa SharePriceRouter --chain arbitrum \
    --constructor-args $(cast abi-encode "constructor(address)" "0x429796dac057e7c15724196367007f1e9cff82f9") \
    --etherscan-api-key $ARBISCAN_API_KEY \
    --watch

echo "Verifying MaxLzEndpoint..."
forge verify-contract 0x168206f71e55241c5d6d51d167566696ccae5525 MaxLzEndpoint --chain arbitrum \
    --constructor-args $(cast abi-encode "constructor(address,address,address)" "0x429796dac057e7c15724196367007f1e9cff82f9" "0x1a44076050125825900e736c501f859c50fE728c" "0xe6d2ac67f3fcb23c6e0babcd2b1c490a1e49cbfa") \
    --etherscan-api-key $ARBISCAN_API_KEY \
    --watch

echo -e "${GREEN}Verification commands completed!${NC}" 