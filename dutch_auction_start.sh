#!/usr/bin/env bash
set -euo pipefail

TOKEN_ADDRESS=0x8f5C717fc9e8727c670a407c3a053B79dD8c88E7
DUTCH_AUCTION=0xDF96d490fc8cf1b14EA25bDb6d26e8D58f6Df0BE
RPC_URL=https://ethereum-sepolia.publicnode.com

: "${PRIVATE_KEY:?PRIVATE_KEY is not set}"

cast send "$DUTCH_AUCTION" \
  "start(address)" \
  "$TOKEN_ADDRESS" \
  --private-key "$PRIVATE_KEY" \
  --rpc-url "$RPC_URL" \
  --gas-limit 3000000