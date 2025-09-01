#!/bin/bash
set -e
source script/utils.sh

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

export CONTRACT_NAME

setup_environment

forge clean

echo "===== Starting $CONTRACT_NAME Deployment ====="
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  "${VERIFY_ARGS[@]}" \
  2>&1 | tee "$LOG_FILE"

# Check that the deployment (although verification may fail) was successful
if ! grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL." "$LOG_FILE"; then
  echo "Error: Deployment failed. Check the log file: $LOG_FILE"
  exit 1
fi


DEPLOYER_ADDRESS=$(grep -E "Deployer address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
PROXY_ADDRESS=$(grep -E "Proxy address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
ADMIN_ADDRESS=$(grep -E "Proxy admin address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
IMPL_ADDRESS=$(grep -E "Implementation address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
OWNER_ADDRESS=$(grep -E "Owner address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
START_TIME=$(grep -E "Start time: " "$LOG_FILE" | tail -1 | awk '{print $NF}')

echo "===== Deployment Complete ====="
echo "Deployer: $DEPLOYER_ADDRESS"
echo "Proxy: $PROXY_ADDRESS"
echo "Admin: $ADMIN_ADDRESS"
echo "Implementation: $IMPL_ADDRESS"
echo "Owner: $OWNER_ADDRESS"
echo "Output saved to: $LOG_FILE"

# Verify deployed contract version
CONTRACT_VERSION=$(cast call "$PROXY_ADDRESS" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')
echo "Contract version: $CONTRACT_VERSION"

semantic_compare "$CONTRACT_VERSION" "$SOURCE_VERSION"
if [ $? -ne 0 ]; then
  echo "Error: Contract version mismatch. Expected $SOURCE_VERSION, got $CONTRACT_VERSION"
  exit 1
fi

GIT_COMMIT=$(git rev-parse --short HEAD)
FULL_SOURCE_VERSION="v${SOURCE_VERSION}-${GIT_COMMIT}"
DEPLOYMENT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}_${FULL_SOURCE_VERSION}_deploy.txt"

echo "Backing up build info for future upgrades..."
BUILD_INFO_BACKUP_DIR=$(backup_build_info "$FULL_SOURCE_VERSION")

cat > "$DEPLOYMENT_FILE" << EOF
CONTRACT_NAME=$CONTRACT_NAME
CHAIN_ID=$CHAIN_ID
DEPLOYER=$DEPLOYER_ADDRESS
PROXY=$PROXY_ADDRESS
ADMIN=$ADMIN_ADDRESS
IMPLEMENTATION=$IMPL_ADDRESS
OWNER=$OWNER_ADDRESS
START_TIME=$START_TIME
VERSION=$FULL_SOURCE_VERSION
REFERENCE_BUILD_INFO_DIR=$BUILD_INFO_BACKUP_DIR
REFERENCE_CONTRACT=build-info-$FULL_SOURCE_VERSION:$CONTRACT_NAME

DEPLOYED_AT=$TIMESTAMP
EOF

echo "Deployment addresses saved to $DEPLOYMENT_FILE"

# Optional: Fund the proxy contract with initial balance (if specified)
if [ -n "$INITIAL_BALANCE" ] && (( $(echo "$INITIAL_BALANCE > 0" | bc -l) )); then
  echo "Funding proxy contract $PROXY_ADDRESS with $INITIAL_BALANCE ether..."
  cast send "$PROXY_ADDRESS" "sendValue()" \
    --value "$(cast --to-wei "$INITIAL_BALANCE" ether)" \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL"
  echo "Funding complete."
fi