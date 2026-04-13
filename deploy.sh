#!/usr/bin/env bash

set -euo pipefail

DEFAULT_RPC_URL="https://ethereum-sepolia.publicnode.com"

if [[ $# -lt 1 ]]; then
	echo "Usage: ./deploy.sh [counter|auction-erc20|dutch-auction|vickrey-auction] [rpc-url(optional)]"
	exit 1
fi

RPC_URL="${2:-$DEFAULT_RPC_URL}"

echo $PRIVATE_KEY

if [[ -z "${PRIVATE_KEY:-}" ]]; then
	echo "Error: PRIVATE_KEY is not set"
	echo "Set it first, for example:"
	echo "  export PRIVATE_KEY=0x<64-hex-private-key>"
	exit 1
fi

DEPLOYER_ADDRESS="$(cast wallet address --private-key "$PRIVATE_KEY")"
BALANCE_WEI="$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL")"

if [[ "$BALANCE_WEI" == "0" ]]; then
	echo "Error: deployer account has 0 ETH on target network"
	echo "  address: $DEPLOYER_ADDRESS"
	echo "  rpc-url: $RPC_URL"
	echo "Fund this address with Sepolia ETH, then retry."
	exit 1
fi

echo "Deployer: $DEPLOYER_ADDRESS"
echo "Balance : $(cast to-unit "$BALANCE_WEI" ether) ETH"

case "$1" in
	counter)
		forge script script/counter.s.sol:CounterScript \
			--rpc-url "$RPC_URL" \
			--broadcast --verify --chain sepolia \
			--gas-limit 3000000
		;;
	auction-erc20)
		forge script script/auctionERC20.s.sol:AuctionERC20Script \
			--rpc-url "$RPC_URL" \
			--broadcast --verify --chain sepolia \
			--gas-limit 6000000
		;;
	dutch-auction)
		forge script script/dutchAuction.s.sol:DutchAuctionScript \
			--rpc-url "$RPC_URL" \
			--broadcast --verify --chain sepolia \
			--gas-limit 6000000
		;;
	vickrey-auction)
		forge script script/vickreyAuction.s.sol:VickreyAuctionScript \
			--rpc-url "$RPC_URL" \
			--broadcast --verify --chain sepolia \
			--gas-limit 6000000
		;;
	*)
		echo "Unknown target: $1"
		echo "Usage: ./deploy.sh [counter|auction-erc20|dutch-auction|vickrey-auction] [rpc-url(optional)]"
		exit 1
		;;
esac

