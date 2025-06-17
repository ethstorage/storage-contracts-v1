#!/bin/bash
set -e

# Load environmental variables
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

output_file="deploy_output_l2.txt"

echo "Deploying contracts..."
forge script script/DeployL2.s.sol \
  --rpc-url "$QKC_TESTNET_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast > "$output_file"

START_TIME=$(grep "Start time:" "$output_file" | head -n1 | awk '{print $3}')
IMPL_ADDRESS=$(grep "Implementation address:" "$output_file" | head -n1 | awk '{print $3}')
PROXY_ADDRESS=$(grep "Proxy address:" "$output_file" | head -n1 | awk '{print $3}')

echo "Implementation deployed at: $IMPL_ADDRESS"
echo "Proxy deployed at: $PROXY_ADDRESS"

echo "Verifying Implementation contract..."
forge verify-contract "$IMPL_ADDRESS" contracts/EthStorageContractL2.sol:EthStorageContractL2 \
  --constructor-args $(cast abi-encode "constructor(uint256[],uint256,uint256,uint256,uint256)" "[$MAX_KV_SIZE_BITS,$SHARD_SIZE_BITS,$RANDOM_CHECKS,$CUTOFF,$DIFF_ADJ_DIVISOR,$TREASURY_SHARE]" $START_TIME $STORAGE_COST $DCF_FACTOR $UPDATE_LIMIT) \
  --rpc-url "$QKC_TESTNET_URL" \
  --verifier-url "$BLOCKSCOUT_API_URL" \
  --verifier blockscout \
  --chain-id 3335 \
  --skip-is-verified-check \
  --watch

echo "Verifying Proxy contract..."
forge verify-contract "$PROXY_ADDRESS" contracts/EthStorageUpgradeableProxy.sol:EthStorageUpgradeableProxy \
  --rpc-url "$QKC_TESTNET_URL" \
  --verifier-url "$BLOCKSCOUT_API_URL" \
  --verifier blockscout \
  --chain-id 3335 \
  --skip-is-verified-check \
  --watch

echo "Deployment and verification complete."