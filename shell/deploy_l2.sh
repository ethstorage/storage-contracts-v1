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

echo "===== Starting EthStorageL2 Deployment =====" | tee -a $OUTPUT_FILE
echo "RPC URL: $RPC_URL" | tee -a $OUTPUT_FILE
echo "Deployment time: $(date)" | tee -a $OUTPUT_FILE

forge script script/DeployEthStorageL2.s.sol:DeployEthStorageL2 \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  --verify \
  --verifier-url "$BLOCKSCOUT_API_URL" \
  --verifier blockscout \
  -vvvv \
  | tee -a $OUTPUT_FILE

IMPL_ADDRESS=$(grep "Implementation address:" $OUTPUT_FILE | awk '{print $3}')
PROXY_ADDRESS=$(grep "Proxy address:" $OUTPUT_FILE | awk '{print $3}')
ADMIN_ADDRESS=$(grep "Proxy admin address:" $OUTPUT_FILE | awk '{print $3}')

echo "===== Deployment Complete =====" | tee -a $OUTPUT_FILE
echo "Implementation: $IMPL_ADDRESS" | tee -a $OUTPUT_FILE
echo "Proxy: $PROXY_ADDRESS" | tee -a $OUTPUT_FILE
echo "Admin: $ADMIN_ADDRESS" | tee -a $OUTPUT_FILE
echo "Output saved to: $OUTPUT_FILE" | tee -a $OUTPUT_FILE

cat > deployments/latest_l2_addresses.txt << EOF
IMPLEMENTATION_ADDRESS=$IMPL_ADDRESS
PROXY_ADDRESS=$PROXY_ADDRESS
ADMIN_ADDRESS=$ADMIN_ADDRESS
DEPLOYMENT_TIME=$(date)
EOF

echo "Deployment addresses saved to deployments/latest_l2_addresses.txt"