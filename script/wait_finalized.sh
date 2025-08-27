#!/bin/bash
set -e

source .env

RPC_URL=${RPC_URL_L2}

 LATEST_BLOCK_NUMBER=$(cast bn latest -r "$RPC_URL")

echo "Waiting for finalized block number to exceed DEPLOYED_BLOCK: $LATEST_BLOCK_NUMBER"

while true; do
  FINALIZED_BLOCK_NUMBER=$(cast bn finalized -r "$RPC_URL")

  echo "Current finalized block number: $FINALIZED_BLOCK_NUMBER"

  if [ "$FINALIZED_BLOCK_NUMBER" -ge "$DEPLOYED_BLOCK" ]; then
    echo "Finalized block number $FINALIZED_BLOCK_NUMBER exceeds or equals DEPLOYED_BLOCK $DEPLOYED_BLOCK"
    break
  fi

  sleep 30
done
