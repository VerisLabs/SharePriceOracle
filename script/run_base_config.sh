#!/bin/bash

# Simple script to configure Base peers for Optimism and Arbitrum

echo "Configuring Base peers for Optimism and Arbitrum..."

# Run the configuration script on Base
forge script script/ConfigBasePeers.sol --rpc-url base --broadcast

echo "Configuration process completed." 