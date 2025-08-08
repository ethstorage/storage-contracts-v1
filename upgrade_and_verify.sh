#!/bin/bash
# filepath: /Users/dl/code/storage-contracts-v1/upgrade_and_verify.sh
set -e

source .env

# <deploy_output_file> must be a .txt file with the following content:
#  Admin address: 0x...
#  Proxy address: 0x...

if [ $# -lt 1 ]; then
  echo "Usage: $0 <deploy_output_file>"
  exit 1
fi

deploy_output="$1"
if [ ! -f "$deploy_output" ]; then
  echo "File $deploy_output not found!"
  exit 1
fi

export PROXY_ADMIN=$(grep -i "Admin address:" "$deploy_output" | awk '{print $3}')
export PROXY=$(grep -i "Proxy address:" "$deploy_output" | awk '{print $3}')

if [ -z "$PROXY_ADMIN" ] || [ -z "$PROXY" ]; then
  echo "Failed to extract Admin or Proxy address from $deploy_output"
  exit 1
fi

echo "Proxy admin: $PROXY_ADMIN"
echo "Proxy: $PROXY"

# export START_TIME=$(grep -i "Start Time:" "$deploy_output" | awk '{print $3}')

export START_TIME=$(cast call "$PROXY" "startTime()(uint256)" --rpc-url "$RPC_URL" | awk '{print $1}')

if [ -z "$START_TIME" ]; then
  echo "Failed to get start time from $PROXY"
  exit 1
fi

echo "Start time: $START_TIME"

prefix=$(echo "$deploy_output" | sed 's/\.txt$//')
timestamp=$(date +"%Y%m%d_%H%M%S")
upgrade_output="${prefix}_upgrade_${timestamp}.txt"

echo "Deploying new implementation contract..."
forge script script/UpgradeL2.s.sol \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast > "$upgrade_output"

NEW_IMPL=$(grep -i "Proxy upgraded to new implementation:" "$upgrade_output" | awk '{print $6}')

if [ -z "$NEW_IMPL" ]; then
  echo "Failed to upgrade contract."
  exit 1
fi

echo "Proxy upgraded to new implementation: $NEW_IMPL" | tee -a "$upgrade_output"

echo "Verifying Implementation contract..."
forge verify-contract "$NEW_IMPL" contracts/EthStorageContractM2L2.sol:EthStorageContractM2L2 \
  --constructor-args $(cast abi-encode "constructor(uint256[],uint256,uint256,uint256,uint256)" "[$MAX_KV_SIZE_BITS,$SHARD_SIZE_BITS,$RANDOM_CHECKS,$CUTOFF,$DIFF_ADJ_DIVISOR,$TREASURY_SHARE]" $START_TIME $STORAGE_COST $DCF_FACTOR $UPDATE_LIMIT) \
  --rpc-url "$RPC_URL" \
  --verifier-url "$BLOCKSCOUT_API_URL" \
  --verifier blockscout \
  --chain-id 3335 \
  --skip-is-verified-check \
  --watch

echo "Upgrade and verification complete." 