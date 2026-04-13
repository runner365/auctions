#!/usr/bin/env bash

TOKEN_ADDRESS=0x8f5C717fc9e8727c670a407c3a053B79dD8c88E7

cast call $TOKEN_ADDRESS "allowance(address,address)(uint256)" \
  0xf01C76F858d72e6cd98357065d9B54F3E783F729 \
  0xDF96d490fc8cf1b14EA25bDb6d26e8D58f6Df0BE \
  --rpc-url https://ethereum-sepolia.publicnode.com


