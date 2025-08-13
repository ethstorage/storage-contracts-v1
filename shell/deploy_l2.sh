#!/bin/bash
set -e

if [ ! -f .env ]; then
  echo "Error: .env file not found."
  exit 1
fi

source .env

mkdir -p deployments

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_FILE="deployments/deploy_l2_${TIMESTAMP}.log"

echo "===== Starting EthStorageL2 Deployment ====="
echo "RPC URL: $RPC_URL"
echo "Deployment time: $(date)"

if [[ "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

forge script script/DeployEthStorageL2.s.sol:DeployEthStorageL2 \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --verify \
  --verifier blockscout \
  --verifier-url "$BLOCKSCOUT_API_URL" \
  -vvvv 2>&1 | tee "$OUTPUT_FILE"

PROXY_ADDRESS=$(grep -E "Proxy address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
ADMIN_ADDRESS=$(grep -E "Proxy admin address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
IMPL_ADDRESS=$(grep -E "Implementation address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
OWNER_ADDRESS=$(grep -E "Owner address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
START_TIME=$(grep -E "Start time: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')

echo "===== Deployment Complete ====="
echo "Proxy: $PROXY_ADDRESS"
echo "Admin: $ADMIN_ADDRESS"
echo "Implementation: $IMPL_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Output saved to: $OUTPUT_FILE"

ADDRESS_FILE="deployments/latest_l2_addresses.txt"

{
  [ -s $ADDRESS_FILE ] && echo
  cat << EOF
PROXY=$PROXY_ADDRESS
ADMIN=$ADMIN_ADDRESS
IMPLEMENTATION=$IMPL_ADDRESS
OWNER=$OWNER_ADDRESS
START_TIME=$START_TIME
DEPLOYMENT_TIME=$(date)
EOF
} >> $ADDRESS_FILE 

echo "Deployment addresses saved to $ADDRESS_FILE"