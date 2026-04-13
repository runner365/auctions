# Auctions

A multi-auction smart contract project built with Foundry. This repository contains several auction mechanisms for selling ERC20 tokens, together with deployment scripts, Foundry tests, and a few shell helpers for Sepolia interaction.

The project currently includes:

- Dutch auction: price decreases over time until a buyer accepts the current price.
- English auction: bidders openly raise bids, and the highest bidder wins after the auction expires.
- Vickrey auction: bidders first commit hashed bids, then reveal them later; the highest bidder wins but pays the second-highest valid bid.
- Auction ERC20 token: a simple ERC20 token used as the auctioned asset in tests and deployment flows.

Note: the repository uses the filename spelling `vickreyAuction.sol`. In auction theory, this is usually written as `Vickrey` auction.

## Tech Stack

- Solidity `^0.8.20`
- Foundry (`forge`, `cast`, `anvil`)
- OpenZeppelin contracts

## Project Structure

```text
src/
	auctionERC20.sol        # ERC20 token used by auctions
	dutchAuction.sol        # Dutch auction implementation
	englishAuction.sol      # English auction implementation
	vickreyAuction.sol      # Commit-reveal second-price auction

script/
	auctionERC20.s.sol      # Deploy AuctionERC20
	dutchAuction.s.sol      # Deploy DutchAuction
	vickreyAuction.s.sol    # Deploy VickreyAuction

test/
	DutchAuction.t.sol
	EnglishAuction.t.sol
	VickreyAuction.t.sol

deploy.sh                 # Unified deploy entry
approve.sh                # Example approval script for Dutch auction
buy.sh                    # Example buy script for Dutch auction
get_current_price.sh      # Read current Dutch auction price
get_status.sh             # Read Dutch auction status
withdraw.sh               # Example withdraw script
```

## Contracts

### AuctionERC20

`AuctionERC20` is a minimal ERC20 contract for local testing and demo deployment.

Constructor parameters:

- `name`
- `symbol`
- `initialSupply`
- `initialAccount`

It mints the full initial supply to the provided account.

### DutchAuction

`DutchAuction` sells a fixed amount of ERC20 tokens. The seller starts the auction by transferring tokens into the contract. The price then decreases linearly from `START_PRICE` to `MIN_PRICE` over a fixed duration.

Core flow:

1. Seller deploys the auction with token amount, start price, minimum price, and duration.
2. Seller approves the auction contract to transfer tokens.
3. Seller calls `start(token)`.
4. Buyers query `getCurrentPrice()` and call `buy()` with enough ETH.
5. If no buyer purchases before expiry, the seller can call `withdraw()` to reclaim tokens.
6. The seller can also call `cancel()` before expiry if the auction is still active.

Highlights:

- Linear descending price.
- Immediate settlement on successful purchase.
- Excess ETH is refunded to the buyer.
- Tokens are escrowed in the contract while the auction is active.

### EnglishAuction

`EnglishAuction` is an open ascending-bid auction for ERC20 tokens. The seller escrows tokens when starting the auction, and bidders compete by sending increasingly higher ETH bids.

Core flow:

1. Seller deploys with token amount and start price.
2. Seller approves the auction contract and calls `startAuction(token, duration)`.
3. Bidders call `bid()` with higher ETH amounts.
4. Outbid bidders accumulate refundable balances in `pendingReturns`.
5. After the auction expires, the seller calls `doneAuction()`.
6. Outbid bidders call `withdraw()` to reclaim their pending ETH.
7. If nobody bids, the seller can call `reclaim()`.

Highlights:

- Highest visible bid wins.
- Previous highest bids are tracked for later withdrawal.
- Seller cannot cancel once active bids exist.

### VickreyAuction

`VickreyAuction` implements a sealed-bid, second-price auction using a commit-reveal flow.

Core phases:

1. `Initialized`
2. `Committing`
3. `Revealing`
4. `EndAuctioned`
5. `EndPhasedOut`

Core flow:

1. Seller deploys with `START_PRICE`, `COMMIT_DURATION`, `REVEAL_DURATION`, and `END_DURATION`.
2. Seller approves the token and calls `startAuction(token, tokenAmount)`.
3. Each bidder computes `keccak256(abi.encodePacked(bidAmount, secret))` off-chain.
4. Each bidder calls `commitBid(bidHash)` and sends ETH as deposit.
5. During reveal phase, each bidder calls `revealBid(bidAmount, secret)`.
6. After reveal phase, anyone can call `endAuction()` during the configured end window.
7. Seller calls `withdrawFund()` to receive the final price.
8. Winner calls `claim()` to receive tokens and any excess deposit refund.
9. Losing bidders call `withdraw()` to reclaim their deposits.

Highlights:

- Hidden bids during commit phase.
- Highest valid bid wins.
- Winner pays second-highest revealed bid when available.
- ETH deposits are used to enforce reveal honesty and cover the bid amount.

## Tests

The repository includes Foundry unit tests for the main auction flows:

- `DutchAuction.t.sol`: token escrow, successful purchase, seller reclaim after expiry, seller cancel.
- `EnglishAuction.t.sol`: reclaim with no bids, cancel restrictions, pending returns withdrawal, final settlement.
- `VickreyAuction.t.sol`: commit/reveal checks, double-commit revert, wrong secret revert, second-price settlement, winner and loser withdrawal paths.

Run all tests:

```bash
forge test
```

Run a specific test file:

```bash
forge test --match-path test/VickreyAuction.t.sol
```

Build only:

```bash
forge build
```

## Installation

If Foundry is not installed:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Install dependencies and build:

```bash
forge install
forge build
```

## Deployment

The project includes a unified deployment entry script:

```bash
./deploy.sh [target] [rpc-url(optional)]
```

Available targets:

- `auction-erc20`
- `dutch-auction`
- `vickrey-auction`

Required environment variable:

```bash
export PRIVATE_KEY=0x<your_private_key>
```

Default RPC endpoint:

```text
https://ethereum-sepolia.publicnode.com
```

Example deployments:

```bash
./deploy.sh auction-erc20
./deploy.sh dutch-auction
./deploy.sh vickrey-auction
```

You can also deploy with Foundry directly.

Deploy AuctionERC20:

```bash
forge script script/auctionERC20.s.sol:AuctionERC20Script \
	--rpc-url <RPC_URL> \
	--broadcast
```

Deploy DutchAuction:

```bash
forge script script/dutchAuction.s.sol:DutchAuctionScript \
	--rpc-url <RPC_URL> \
	--broadcast
```

Deploy VickreyAuction:

```bash
forge script script/vickreyAuction.s.sol:VickreyAuctionScript \
	--rpc-url <RPC_URL> \
	--broadcast
```

### Deployment Parameters

`auctionERC20.s.sol` reads:

- `PRIVATE_KEY`
- `TOKEN_NAME` with default `Auction Token`
- `TOKEN_SYMBOL` with default `AUCT`
- `INITIAL_SUPPLY` with default `1000000 ether`
- `INITIAL_ACCOUNT` with default deployer address

`dutchAuction.s.sol` reads:

- `PRIVATE_KEY`
- `TOKEN_AMOUNT` with default `100 ether`
- `START_PRICE` with default `1 ether`
- `MIN_PRICE` with default `0.01 ether`
- `DURATION` with default `5 minutes`

`vickreyAuction.s.sol` reads:

- `PRIVATE_KEY`
- `START_PRICE` with default `1 ether`
- `COMMIT_DURATION` with default `5 minutes`
- `REVEAL_DURATION` with default `5 minutes`
- `END_DURATION` with default `5 minutes`

## Helper Shell Scripts

The root directory includes several quick scripts aimed at Sepolia interaction:

- `approve.sh`: approve ERC20 tokens for the Dutch auction contract.
- `buy.sh`: buy from a deployed Dutch auction.
- `get_current_price.sh`: read the current Dutch auction price.
- `get_status.sh`: read the Dutch auction status enum value.
- `withdraw.sh`: call `withdraw()` on a deployed contract instance.

These scripts currently contain hardcoded contract addresses and are best treated as local utilities or examples. Review and update addresses, private keys, and RPC URLs before using them.

## Example Local Workflow

Start a local chain:

```bash
anvil
```

In another terminal, run tests:

```bash
forge test -vv
```

Optionally deploy a token and auction to the local node:

```bash
export PRIVATE_KEY=<anvil_private_key>
forge script script/auctionERC20.s.sol:AuctionERC20Script --rpc-url http://127.0.0.1:8545 --broadcast
forge script script/dutchAuction.s.sol:DutchAuctionScript --rpc-url http://127.0.0.1:8545 --broadcast
```

## Security Notes

- The contracts use `ReentrancyGuard` and OpenZeppelin `SafeERC20` for core token and ETH transfer flows.
- This repository looks like a learning or prototype project rather than a production-ready auction platform.
- The contracts have not been audited.
- Before mainnet usage, you should add broader invariant testing, fuzzing, access-control review, and explicit handling for edge cases around timing and unrevealed bids.

## Summary

This repository is a compact Foundry playground for comparing three classic auction designs in Solidity:

- Dutch auction for fast descending-price sales.
- English auction for public competitive bidding.
- Vickrey auction for sealed-bid second-price settlement.

It is useful for learning auction mechanisms, testing ERC20 escrow patterns, and experimenting with Foundry-based deployment and test workflows.
