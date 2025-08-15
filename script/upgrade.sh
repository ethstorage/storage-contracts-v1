#!/bin/bash
set -e

if [ $# -eq 0 ]; then
  echo "Usage: $0 <deployment_file>"
  echo "Example: $0 deployments/EthStorageContractM2L2_31337.txt"
  exit 1
fi

# Go to project root directory
cd "$(dirname "$0")/.."

DEPLOYMENT_FILE=$1

if [ ! -f "$DEPLOYMENT_FILE" ]; then
  echo "Error: Deployment file '$DEPLOYMENT_FILE' not found."
  exit 1
fi

if [ ! -f .env ]; then
  echo "Error: .env file not found."
  exit 1
fi

# Load base environment
source .env

# Load deployment information
echo "Loading deployment information from: $DEPLOYMENT_FILE"
source "$DEPLOYMENT_FILE"

# Debug: Print loaded variables
echo "Loaded REFERENCE_BUILD_INFO_DIR: '$REFERENCE_BUILD_INFO_DIR'"
echo "Loaded REFERENCE_CONTRACT: '$REFERENCE_CONTRACT'"

echo "===== Starting $CONTRACT_NAME Upgrade ====="
echo "Deployment file: $DEPLOYMENT_FILE"
echo "Chain ID: $CHAIN_ID"
echo "Proxy address: $PROXY"

# Validate required variables
if [ -z "$PROXY" ]; then
  echo "Error: PROXY address not found in deployment file"
  exit 1
fi

if [ -z "$START_TIME" ]; then
  echo "Error: START_TIME not found in deployment file"
  exit 1
fi

# Export required variables for Solidity script
export CONTRACT_NAME
export PROXY
export START_TIME

# Only export reference variables if they exist and are not empty
if [ -n "$REFERENCE_BUILD_INFO_DIR" ]; then
  export REFERENCE_BUILD_INFO_DIR
  echo "Using reference build info dir: $REFERENCE_BUILD_INFO_DIR"
else
  echo "Error: REFERENCE_BUILD_INFO_DIR not set or empty"
  exit 1
fi

if [ -n "$REFERENCE_CONTRACT" ]; then
  export REFERENCE_CONTRACT
  echo "Using reference contract: $REFERENCE_CONTRACT"
else
  echo "Error: REFERENCE_CONTRACT not set or empty"
  exit 1
fi

# Set L1/L2 specific parameters based on contract name
VERIFY_ARGS=()
if [[ "$CONTRACT_NAME" == *L2 ]]; then
  export STORAGE_COST="$STORAGE_COST_L2"
  export MINIMUM_DIFF="$MINIMUM_DIFF_L2"
  export PREPAID_AMOUNT="$PREPAID_AMOUNT_L2"
  RPC_URL="$RPC_URL_L2"
  VERIFY_ARGS+=(--verify --verifier blockscout --verifier-url "$BLOCKSCOUT_API_URL")
else
  export STORAGE_COST="$STORAGE_COST_L1"
  export MINIMUM_DIFF="$MINIMUM_DIFF_L1"
  export PREPAID_AMOUNT="$PREPAID_AMOUNT_L1"
  RPC_URL="$RPC_URL_L1"
  VERIFY_ARGS+=(--verify --etherscan-api-key "$ETHERSCAN_API_KEY")
fi

# Ensure private key has 0x prefix
if [[ "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

# Skip verification for local chain
if [ "$CHAIN_ID" -eq 31337 ]; then
  VERIFY_ARGS=()
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
UPGRADE_OUTPUT_FILE="deployments/logs/${TIMESTAMP}_${CHAIN_ID}_${CONTRACT_NAME}_upgrade.log"

echo "RPC URL: $RPC_URL"

# Execute upgrade
echo "Executing upgrade..."
forge script script/Deploy.s.sol:Deploy \
  --sig "upgrade()" \
  --rpc-url "$RPC_URL" \
  --broadcast \
  "${VERIFY_ARGS[@]}" \
  -vvvv 2>&1 | tee "$UPGRADE_OUTPUT_FILE"

# Extract new implementation address
NEW_IMPL_ADDRESS=$(grep -E "New implementation address: " "$UPGRADE_OUTPUT_FILE" | tail -1 | awk '{print $NF}')
if [ -z "$NEW_IMPL_ADDRESS" ]; then
  echo "Error: New implementation address not found. Check $UPGRADE_OUTPUT_FILE"
  exit 1
fi

echo "===== Upgrade Complete ====="
echo "Proxy: $PROXY (unchanged)"
echo "Old Implementation: $IMPLEMENTATION"
echo "New Implementation: $NEW_IMPL_ADDRESS"
echo "Upgrade log saved to: $UPGRADE_OUTPUT_FILE"

echo "Verifying upgrade by checking contract version..."
NEW_VERSION=$(cast call "$PROXY" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')
echo "Contract version after upgrade: $NEW_VERSION"

OLD_VERSION=$(grep -E "^VERSION=" "$DEPLOYMENT_FILE" | cut -d'=' -f2 || echo "unknown")

# Update deployment file with new implementation
UPDATED_DEPLOYMENT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}_${NEW_VERSION}.txt"

cat > "$UPDATED_DEPLOYMENT_FILE" << EOF
CONTRACT_NAME=$CONTRACT_NAME
CHAIN_ID=$CHAIN_ID
DEPLOYER=$DEPLOYER
PROXY=$PROXY
ADMIN=$ADMIN
IMPLEMENTATION=$NEW_IMPL_ADDRESS
OWNER=$OWNER
START_TIME=$START_TIME
DEPLOYED_AT=$DEPLOYED_AT
UPGRADED_AT=$TIMESTAMP
PREVIOUS_IMPLEMENTATION=$IMPLEMENTATION
PREVIOUS_VERSION=$OLD_VERSION
VERSION=$NEW_VERSION
REFERENCE_BUILD_INFO_DIR=$REFERENCE_BUILD_INFO_DIR
REFERENCE_CONTRACT=$REFERENCE_CONTRACT
EOF

echo "Updated deployment info saved to: $UPDATED_DEPLOYMENT_FILE"

# Backup build info for future upgrades
echo "Backing up build info for future upgrades..."
BUILD_INFO_BACKUP_DIR="old-builds/build-info-v$NEW_VERSION"
if [ -d "out/build-info" ]; then
  mkdir -p "old-builds"
  cp -r out/build-info "$BUILD_INFO_BACKUP_DIR"
  echo "Build info backed up to: $BUILD_INFO_BACKUP_DIR"
else
  echo "Warning: out/build-info directory not found, skipping backup"
fi