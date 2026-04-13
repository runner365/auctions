#!/usr/bin/env bash

set -euo pipefail

new_private_key=$PRIVATE_KEY1
value=400000000000000000
cast send 0xDF96d490fc8cf1b14EA25bDb6d26e8D58f6Df0BE "buy()" \
  --value $value \
  --private-key $new_private_key \
  --rpc-url https://ethereum-sepolia.publicnode.com
