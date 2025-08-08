#!/bin/bash
set -e

if [ ! -f .env ]; then
  echo "Error: .env file not found. Please copy .env.sample to .env and fill in your values."
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
  --verifier-url "$BLOCKSCOUT_API_URL" \
  --verifier blockscout

IMPL_ADDRESS=$(grep "Implementation address:" $OUTPUT_FILE | awk '{print $6}')
PROXY_ADDRESS=$(grep "Proxy address:" $OUTPUT_FILE | awk '{print $3}')
ADMIN_ADDRESS=$(grep "Proxy admin address:" $OUTPUT_FILE | awk '{print $3}')

echo "===== Deployment Complete ====="
echo "Implementation: $IMPL_ADDRESS" 
echo "Proxy: $PROXY_ADDRESS"
echo "Admin: $ADMIN_ADDRESS"
echo "Output saved to: $OUTPUT_FILE"

cat > deployments/latest_l2_addresses.txt << EOF
IMPLEMENTATION_ADDRESS=$IMPL_ADDRESS
PROXY_ADDRESS=$PROXY_ADDRESS
ADMIN_ADDRESS=$ADMIN_ADDRESS
DEPLOYMENT_TIME=$(date)
EOF

echo "Deployment addresses saved to deployments/latest_l2_addresses.txt"