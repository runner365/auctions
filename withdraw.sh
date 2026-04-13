#!/usr/bin/env bash

set -euo pipefail

cast send 0xbd42E491eB498948A5490Ec6b16Cf2BD64686AbE "withdraw()" \
  --private-key $PRIVATE_KEY \
  --rpc-url https://ethereum-sepolia.publicnode.com
