#!/bin/bash
set -e
source script/utils.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 <deployment_file>"
  echo "Example: $0 deployments/EthStorageContractM2_31337_v0.2.0-108c728_deploy.txt"
  exit 1
fi

export DEPLOYMENT_FILE=$1

setup_upgrade_environment
setup_environment
check_upgrade_versions

forge clean

echo "===== Starting $CONTRACT_NAME Upgrade ====="
forge script script/Deploy.s.sol:Deploy \
  --sig "upgrade()" \
  --rpc-url "$RPC_URL" \
  --broadcast \
  --retries 30 \
  --delay 10 \
  "${VERIFY_ARGS[@]}" \
  2>&1 | tee "$LOG_FILE"

# Check that the upgrade (although verification may fail) was successful
if ! grep -q "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL." "$LOG_FILE"; then
  echo "Error: Upgrade failed. Check the log file: $LOG_FILE"
  exit 1
fi

# Extract new implementation address
NEW_IMPL_ADDRESS=$(grep -E "New implementation address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
if [ -z "$NEW_IMPL_ADDRESS" ]; then
  echo "Error: New implementation address not found. Check $LOG_FILE"
  exit 1
fi

echo "===== Upgrade Complete ====="
echo "Old Implementation: $IMPLEMENTATION"
echo "New Implementation: $NEW_IMPL_ADDRESS"
echo "Upgrade log saved to: $LOG_FILE"

echo "Verifying upgrade by checking contract version..."
NEW_VERSION=$(cast call "$PROXY" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')

semantic_compare "$NEW_VERSION" "$SOURCE_VERSION"
if [ $? -ne 0 ]; then
  echo "Error: Contract version mismatch after upgrade. Expected $SOURCE_VERSION, got $NEW_VERSION"
  exit 1
fi

GIT_COMMIT=$(git rev-parse --short HEAD)
FULL_SOURCE_VERSION="v${SOURCE_VERSION}-${GIT_COMMIT}"
DEPLOYMENT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}_${FULL_SOURCE_VERSION}_upgrade.txt"

echo "Backing up build info for future upgrades..."
BUILD_INFO_BACKUP_DIR=$(backup_build_info "$FULL_SOURCE_VERSION")

OWNER_ADDRESS=$(grep -E "Owner address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')
DEPLOYER_ADDRESS=$(grep -E "Deployer address: " "$LOG_FILE" | tail -1 | awk '{print $NF}')

cat > "$DEPLOYMENT_FILE" << EOF
CONTRACT_NAME=$CONTRACT_NAME
CHAIN_ID=$CHAIN_ID
DEPLOYER=$DEPLOYER_ADDRESS
PROXY=$PROXY
ADMIN=$ADMIN
IMPLEMENTATION=$NEW_IMPL_ADDRESS
OWNER=$OWNER_ADDRESS
START_TIME=$START_TIME
VERSION=$FULL_SOURCE_VERSION
REFERENCE_BUILD_INFO_DIR=$BUILD_INFO_BACKUP_DIR
REFERENCE_CONTRACT=build-info-$FULL_SOURCE_VERSION:$CONTRACT_NAME

DEPLOYED_AT=$DEPLOYED_AT
UPGRADED_AT=$TIMESTAMP
EOF

echo "Updated deployment info saved to: $DEPLOYMENT_FILE"