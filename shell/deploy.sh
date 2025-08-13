#!/bin/bash
set -e

if [ $# -eq 0 ]; then
  echo "Usage: $0 <contract_type>"
  echo "Contract types:"
  echo "  11 - EthStorageContractM1"
  echo "  12 - EthStorageContractM1L2"
  echo "  21 - EthStorageContractM2"
  echo "  22 - EthStorageContractM2L2"
  exit 1
fi

CONTRACT_TYPE=$1

case $CONTRACT_TYPE in
  11)
    CONTRACT_NAME="EthStorageContractM1"
    ;;
  12)
    CONTRACT_NAME="EthStorageContractM1L2"
    ;;
  21)
    CONTRACT_NAME="EthStorageContractM2"
    ;;
  22)
    CONTRACT_NAME="EthStorageContractM2L2"
    ;;
  *)
    echo "Error: Invalid contract type '$CONTRACT_TYPE'"
    echo "Valid types: 11, 12, 21, 22"
    exit 1
    ;;
esac

if [ ! -f .env ]; then
  echo "Error: .env file not found."
  exit 1
fi

source .env

# Export CONTRACT_NAME and L1/L2 specific parameters for the Solidity script
export CONTRACT_NAME

VERIFY_ARGS=()
if [[ "$CONTRACT_NAME" == *L2 ]]; then
  export STORAGE_COST="$STORAGE_COST_L2"
  export MINIMUM_DIFF="$MINIMUM_DIFF_L2"
  export PREPAID_AMOUNT="$PREPAID_AMOUNT_L2"
  export INITIAL_BALANCE="$INITIAL_BALANCE_L2"
  VERIFY_ARGS+=(--verify --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL")
else
  export STORAGE_COST="$STORAGE_COST_L1"
  export MINIMUM_DIFF="$MINIMUM_DIFF_L1"
  export PREPAID_AMOUNT="$PREPAID_AMOUNT_L1"
  export INITIAL_BALANCE="$INITIAL_BALANCE_L1"
  VERIFY_ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

mkdir -p deployments

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
OUTPUT_FILE="deployments/${TIMESTAMP}_${CHAIN_ID}_${CONTRACT_TYPE}.log"

echo "===== Starting $CONTRACT_NAME Deployment ====="
echo "RPC URL: $RPC_URL"
echo "Chain ID: $CHAIN_ID"

if [[ "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

if [ "$CHAIN_ID" -eq 31337 ]; then
  VERIFY_ARGS=()
fi

forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  "${VERIFY_ARGS[@]}" \
  -vvvv 2>&1 | tee "$OUTPUT_FILE"

DEPLOYER_ADDRESS=$(grep -E "Deployer address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
PROXY_ADDRESS=$(grep -E "Proxy address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
ADMIN_ADDRESS=$(grep -E "Proxy admin address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
IMPL_ADDRESS=$(grep -E "Implementation address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
OWNER_ADDRESS=$(grep -E "Owner address: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')
START_TIME=$(grep -E "Start time: " "$OUTPUT_FILE" | tail -1 | awk '{print $NF}')

echo "===== Deployment Complete ====="
echo "Deployer: $DEPLOYER_ADDRESS"
echo "Proxy: $PROXY_ADDRESS"
echo "Admin: $ADMIN_ADDRESS"
echo "Implementation: $IMPL_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Output saved to: $OUTPUT_FILE"

RESULT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}.txt"

cat > "$RESULT_FILE" << EOF
CHAIN_ID=$CHAIN_ID
DEPLOYER_ADDRESS=$DEPLOYER_ADDRESS
PROXY=$PROXY_ADDRESS
ADMIN=$ADMIN_ADDRESS
IMPLEMENTATION=$IMPL_ADDRESS
OWNER=$OWNER_ADDRESS
START_TIME=$START_TIME
Deployed at $TIMESTAMP
EOF

echo "Deployment addresses saved to $RESULT_FILE"

if [ -n "$INITIAL_BALANCE" ] && (( $(echo "$INITIAL_BALANCE > 0" | bc -l) )); then
  echo "Funding proxy contract $PROXY_ADDRESS with $INITIAL_BALANCE ether..."
  cast send "$PROXY_ADDRESS" "sendValue()" \
    --value "$(cast --to-wei "$INITIAL_BALANCE" ether)" \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" -vvvv
  echo "Funding complete."
fi