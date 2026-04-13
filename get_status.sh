#!/usr/bin/env bash

set -euo pipefail

AUCTION_ADDRESS=0xDF96d490fc8cf1b14EA25bDb6d26e8D58f6Df0BE
RPC_URL=https://ethereum-sepolia.publicnode.com

STATUS=$(cast call "$AUCTION_ADDRESS" "status()(uint8)" --rpc-url "$RPC_URL")

echo "Auction address: $AUCTION_ADDRESS"
echo "Status (uint8): $STATUS"
echo "Enum mapping: 0=Initialized, 1=Active, 2=Sold, 3=Cancelled, 4=Expired"
