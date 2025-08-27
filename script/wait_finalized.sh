#!/bin/bash
set -e

source .env
source $(ls -t deployments/EthStorageContractM2L2*.txt | head -n 1)

RPC_URL=${RPC_URL_L2}

if [ -z "$DEPLOYED_BLOCK" ]; then
  echo "Please set DEPLOYED_BLOCK environment variable"
  exit 1
fi

echo "Waiting for finalized block number to exceed DEPLOYED_BLOCK: $DEPLOYED_BLOCK"

while true; do
  FINALIZED_BLOCK_NUMBER=$(cast bn finalized -r "$RPC_URL")

  echo "Current finalized block number: $FINALIZED_BLOCK_NUMBER"

  if [ "$FINALIZED_BLOCK_NUMBER" -ge "$DEPLOYED_BLOCK" ]; then
    echo "Finalized block number $FINALIZED_BLOCK_NUMBER exceeds or equals DEPLOYED_BLOCK $DEPLOYED_BLOCK"
    break
  fi

  sleep 30
done
