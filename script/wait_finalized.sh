#!/bin/bash
set -e

source .env

RPC_URL=${RPC_URL_L2}

LATEST_BLOCK_NUMBER=$(cast bn latest -r "$RPC_URL")

echo "Waiting for finalized block number to exceed LATEST_BLOCK_NUMBER: $LATEST_BLOCK_NUMBER"

while true; do
  FINALIZED_BLOCK_NUMBER=$(cast bn finalized -r "$RPC_URL")

  echo "Current finalized block number: $FINALIZED_BLOCK_NUMBER"

  if [ "$FINALIZED_BLOCK_NUMBER" -ge "$LATEST_BLOCK_NUMBER" ]; then
    echo "Finalized block number $FINALIZED_BLOCK_NUMBER exceeds or equals LATEST_BLOCK_NUMBER $LATEST_BLOCK_NUMBER"
    break
  fi

  sleep 30
done
