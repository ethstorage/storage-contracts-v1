#!/bin/bash
set -e

source .env

RPC_URL=${RPC_URL_L2}
START_TIME=${START_TIME}

if [ -z "$START_TIME" ]; then
  echo "Please set START_TIME environment variable"
  exit 1
fi

echo "Waiting for finalized block time to exceed START_TIME: $START_TIME"

while true; do
  FINALIZED_BLOCK_JSON=$(cast rpc --rpc-url "$RPC_URL" eth_getBlockByNumber finalized true)

  BLOCK_TIMESTAMP_HEX=$(echo "$FINALIZED_BLOCK_JSON" | jq -r '.timestamp')
  BLOCK_TIMESTAMP=$(printf "%d" "$BLOCK_TIMESTAMP_HEX")

  echo "Current finalized block timestamp: $BLOCK_TIMESTAMP"

  if [ "$BLOCK_TIMESTAMP" -gt "$START_TIME" ]; then
    echo "Finalized block timestamp $BLOCK_TIMESTAMP exceeds START_TIME $START_TIME"
    break
  fi

  sleep 30
done