#!/bin/bash
set -e

# Manual upgrade via ProxyAdmin.upgradeAndCall

if [ $# -ne 1 ]; then
  echo "Usage: $0 <deployment_file>"
  echo "Example: $0 deployments/EthStorageContractM2_31337_v0.2.0-108c728_prepare.txt"
  exit 1
fi

# Go to project root
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

source .env
source "$DEPLOYMENT_FILE"

if [ -z "$PROXY" ]; then
  echo "Error: PROXY not set in deployment file."
  exit 1
fi
if [ -z "$ADMIN" ]; then
  echo "Error: ADMIN (ProxyAdmin) not set in deployment file."
  exit 1
fi
if [ -z "$IMPLEMENTATION" ]; then
  echo "Error: IMPLEMENTATION (prepared impl) not set in deployment file."
  exit 1
fi

# Warn if not prepared
if [ -z "${PREPARED_AT:-}" ]; then
  echo "⚠️  PREPARED_AT not found in $DEPLOYMENT_FILE (implementation may not be prepared)."
  read -p "Continue with manual upgrade anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Manual upgrade cancelled."
    exit 0
  fi
else
  echo "Prepared at: $PREPARED_AT"
fi

# Choose RPC URL based on contract type
if [[ "$CONTRACT_NAME" == *L2 ]]; then
  RPC_URL="$RPC_URL_L2"
else
  RPC_URL="$RPC_URL_L1"
fi
if [ -z "$RPC_URL" ]; then
  echo "Error: RPC_URL not resolved (check .env for RPC_URL_L1/RPC_URL_L2)."
  exit 1
fi

CUR_VERSION=$(cast call "$PROXY" "version()" --rpc-url "$RPC_URL" | cast --to-ascii | tr -d ' ')
echo "Current on-chain version: $CUR_VERSION"

# Ensure private key has 0x prefix
if [[ "${PRIVATE_KEY:-}" != 0x* ]]; then
  PRIVATE_KEY="0x$PRIVATE_KEY"
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
mkdir -p "deployments/logs"
LOG_FILE="deployments/logs/${TIMESTAMP}_${CONTRACT_NAME}_${CHAIN_ID}_manually.log"

UPGRADE_DATA="${UPGRADE_DATA:-0x}"

echo "===== Manual upgrade via ProxyAdmin.upgradeAndCall =====" | tee "$LOG_FILE"
echo "Contract:      $CONTRACT_NAME" | tee -a "$LOG_FILE"
echo "Chain ID:      $CHAIN_ID" | tee -a "$LOG_FILE"
echo "Proxy:         $PROXY" | tee -a "$LOG_FILE"
echo "ProxyAdmin:    $ADMIN" | tee -a "$LOG_FILE"
echo "Implementation:$IMPLEMENTATION" | tee -a "$LOG_FILE"
echo "Calldata:      $UPGRADE_DATA" | tee -a "$LOG_FILE"
echo "RPC URL:       $RPC_URL" | tee -a "$LOG_FILE"

TX_HASH=$(cast send "$ADMIN" "upgradeAndCall(address,address,bytes)" "$PROXY" "$IMPLEMENTATION" "$UPGRADE_DATA" \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" | grep -Eo '0x[0-9a-fA-F]{64}' | head -1 || true)
if [ -z "$TX_HASH" ]; then
  echo "Error: failed to send upgrade tx" | tee -a "$LOG_FILE"
  exit 1
fi
echo "Tx sent: $TX_HASH" | tee -a "$LOG_FILE"

# Verify new implementation via cast proxy-implementation
NEW_IMPL_ONCHAIN=$(cast implementation "$PROXY" --rpc-url "$RPC_URL")
if [[ -z "$NEW_IMPL_ONCHAIN" || ! "$NEW_IMPL_ONCHAIN" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "Error: failed to fetch implementation via cast proxy-implementation" | tee -a "$LOG_FILE"
  exit 1
fi
if [ "$(echo "$NEW_IMPL_ONCHAIN" | tr '[:upper:]' '[:lower:]')" != "$(echo "$IMPLEMENTATION" | tr '[:upper:]' '[:lower:]')" ]; then
  echo "Error: on-chain implementation ($NEW_IMPL_ONCHAIN) differs from intended ($IMPLEMENTATION)" | tee -a "$LOG_FILE"
  exit 1
fi
echo "New implementation address (on-chain): $NEW_IMPL_ONCHAIN" | tee -a "$LOG_FILE"

# Version from proxy
NEW_VERSION=$(cast call "$PROXY" "version()" --rpc-url "$RPC_URL" 2>/dev/null | cast --to-ascii | tr -d ' ' || echo "unknown")
echo "Contract on-chain version after upgrade: $NEW_VERSION" | tee -a "$LOG_FILE"

# Save updated deployment info
UPDATED_DEPLOYMENT_FILE="deployments/${CONTRACT_NAME}_${CHAIN_ID}_${VERSION}_manual.txt"
cat > "$UPDATED_DEPLOYMENT_FILE" << EOF
CONTRACT_NAME=$CONTRACT_NAME
CHAIN_ID=$CHAIN_ID
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
PROXY=$PROXY
ADMIN=$ADMIN
IMPLEMENTATION=$NEW_IMPL_ONCHAIN
OWNER=$OWNER
START_TIME=$START_TIME
VERSION=$VERSION
REFERENCE_BUILD_INFO_DIR=${REFERENCE_BUILD_INFO_DIR}
REFERENCE_CONTRACT=${REFERENCE_CONTRACT}

DEPLOYED_AT=$DEPLOYED_AT
MANUALLY_UPGRADED_AT=$TIMESTAMP
EOF

echo "Updated deployment info saved to: $UPDATED_DEPLOYMENT_FILE"
echo "Manual upgrade complete."