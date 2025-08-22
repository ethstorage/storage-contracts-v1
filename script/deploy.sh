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

# Go to project root directory
cd "$(dirname "$0")/.."

# Extract version from current source code
if [ -f "contracts/EthStorageContract.sol" ]; then
  current_version=$(grep -E 'string public constant version = ' contracts/EthStorageContract.sol | sed -E 's/.*version = "([^"]+)".*/\1/' | tr -d ' ')
else
  echo "Error: contracts/EthStorageContract.sol not found"
  return 2
fi

echo "Current source code version: v$current_version"

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
  RPC_URL="$RPC_URL_L2"
  VERIFY_ARGS+=(--verify --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL")
else
  export STORAGE_COST="$STORAGE_COST_L1"
  export MINIMUM_DIFF="$MINIMUM_DIFF_L1"
  export PREPAID_AMOUNT="$PREPAID_AMOUNT_L1"
  export INITIAL_BALANCE="$INITIAL_BALANCE_L1"
  RPC_URL="$RPC_URL_L1"
  VERIFY_ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

mkdir -p deployments/logs

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL")
OUTPUT_FILE="deployments/logs/${TIMESTAMP}_${CONTRACT_NAME}_${CHAIN_ID}.log"

# To avoid Error - `Build info file ${buildInfoFilePath} is not from a full compilation.`
forge clean & forge build

echo "RPC URL: $RPC_URL"
echo "Chain ID: $CHAIN_ID"

if [[ "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

if [ "$CHAIN_ID" -eq 31337 ]; then
  VERIFY_ARGS=()
fi

echo "===== Starting $CONTRACT_NAME Deployment ====="
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  --broadcast \
  "${VERIFY_ARGS[@]}" \
  -vvvv 2>&1 | tee "$OUTPUT_FILE"

# Check if deployment was successful
status=${PIPESTATUS[0]}
if [ "$status" -ne 0 ]; then
  echo "Deployment failed. Check the log file: $OUTPUT_FILE"
  exit 1
fi

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

echo "Querying contract version..."
CONTRACT_VERSION=$(cast call "$PROXY_ADDRESS" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')
echo "Contract version: $CONTRACT_VERSION"

# Backup build info for future upgrades
echo "Backing up build info for future upgrades..."
GIT_COMMIT=$(git rev-parse --short HEAD)
echo "⎇ git commit: $GIT_COMMIT"
FULL_CONTRACT_VERSION="v${CONTRACT_VERSION}-${GIT_COMMIT}"
BUILD_INFO_BACKUP_DIR="old-builds/build-info-${FULL_CONTRACT_VERSION}"
if [ -d "$BUILD_INFO_BACKUP_DIR" ]; then
  echo "Removing existing backup directory: $BUILD_INFO_BACKUP_DIR"
  rm -rf "$BUILD_INFO_BACKUP_DIR"
fi
mkdir -p "old-builds"
cp -r out/build-info "$BUILD_INFO_BACKUP_DIR"
echo "Build info backed up to: $BUILD_INFO_BACKUP_DIR"

DEPLOYMENT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}_${FULL_CONTRACT_VERSION}.txt"

cat > "$DEPLOYMENT_FILE" << EOF
CONTRACT_NAME=$CONTRACT_NAME
CHAIN_ID=$CHAIN_ID
DEPLOYER=$DEPLOYER_ADDRESS
PROXY=$PROXY_ADDRESS
ADMIN=$ADMIN_ADDRESS
IMPLEMENTATION=$IMPL_ADDRESS
OWNER=$OWNER_ADDRESS
START_TIME=$START_TIME
VERSION=$FULL_CONTRACT_VERSION
REFERENCE_BUILD_INFO_DIR=$BUILD_INFO_BACKUP_DIR
REFERENCE_CONTRACT=build-info-$FULL_CONTRACT_VERSION:$CONTRACT_NAME

DEPLOYED_AT=$TIMESTAMP
EOF

echo "Deployment addresses saved to $DEPLOYMENT_FILE"

if [ -n "$INITIAL_BALANCE" ] && (( $(echo "$INITIAL_BALANCE > 0" | bc -l) )); then
  echo "Funding proxy contract $PROXY_ADDRESS with $INITIAL_BALANCE ether..."
  cast send "$PROXY_ADDRESS" "sendValue()" \
    --value "$(cast --to-wei "$INITIAL_BALANCE" ether)" \
    --private-key "$PRIVATE_KEY" --rpc-url "$RPC_URL" -vvvv
  echo "Funding complete."
fi