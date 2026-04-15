// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DutchAuction} from "../src/dutchAuction.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";

contract DutchAuctionTest is Test {
    DutchAuction internal auction;
    AuctionERC20 internal token;

    address internal seller;
    address internal buyer;

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant TOKEN_AMOUNT = 100 ether;
    uint256 internal constant START_PRICE = 10 ether;
    uint256 internal constant MIN_PRICE = 1 ether;
    uint256 internal constant DURATION = 1 days;

    function setUp() public {
        seller = makeAddr("seller");
        buyer = makeAddr("buyer");

        vm.deal(buyer, 100 ether);

        vm.startPrank(seller);
        token = new AuctionERC20("Auction Token", "AUCT", INITIAL_SUPPLY, seller);
        auction = new DutchAuction(TOKEN_AMOUNT, START_PRICE, MIN_PRICE, DURATION);

        token.approve(address(auction), TOKEN_AMOUNT);
        auction.start(address(token));
        vm.stopPrank();
    }

    function testStartTransfersTokensIntoAuction() public view {
        assertEq(token.balanceOf(address(auction)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);
        assertEq(uint256(auction.status()), 1); // Active
    }

    function testBuyTransfersTokenRefundsExcessAndPaysSeller() public {
        vm.warp(block.timestamp + DURATION / 2);

        uint256 currentPrice = auction.getCurrentPriceByAmount(auction.tokenAmount());
        uint256 excess = 1 ether;
        uint256 sellerBalanceBefore = seller.balance;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        auction.buy{value: currentPrice + excess}();

        assertEq(token.balanceOf(buyer), TOKEN_AMOUNT);
        assertEq(seller.balance, sellerBalanceBefore + currentPrice);
        assertEq(buyer.balance, buyerBalanceBefore - currentPrice);
        assertEq(address(auction).balance, 0);
        assertEq(uint256(auction.status()), 2); // Sold
    }

    function testWithdrawAfterExpiryReturnsTokensToSeller() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.withdraw();

        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(auction)), 0);
        assertEq(uint256(auction.status()), 4); // Expired
    }

    function testCancelReturnsTokensToSeller() public {
        vm.prank(seller);
        auction.cancel();

        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(auction)), 0);
        assertEq(uint256(auction.status()), 3); // Cancelled
    }

    // ─── buySomeToken ──────────────────────────────────────────────────────────

    function testBuySomeTokenPartialPurchaseUpdatesState() public {
        uint256 buyAmount = 40 ether;
        uint256 price = auction.getCurrentPriceByAmount(buyAmount);

        vm.prank(buyer);
        auction.buySomeToken{value: price}(buyAmount);

        assertEq(token.balanceOf(buyer), buyAmount);
        assertEq(token.balanceOf(address(auction)), TOKEN_AMOUNT - buyAmount);
        assertEq(auction.tokenAmount(), TOKEN_AMOUNT - buyAmount);
        assertEq(uint256(auction.status()), 1); // still Active
        assertEq(address(auction).balance, 0);
    }

    function testBuySomeTokenRefundsExcess() public {
        uint256 buyAmount = 40 ether;
        uint256 price = auction.getCurrentPriceByAmount(buyAmount);
        uint256 excess = 1 ether;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        auction.buySomeToken{value: price + excess}(buyAmount);

        assertEq(buyer.balance, buyerBalanceBefore - price);
        assertEq(address(auction).balance, 0);
    }

    function testBuySomeTokenSetsStatusSoldWhenAllBought() public {
        uint256 price = auction.getCurrentPriceByAmount(TOKEN_AMOUNT);

        vm.prank(buyer);
        auction.buySomeToken{value: price}(TOKEN_AMOUNT);

        assertEq(auction.tokenAmount(), 0);
        assertEq(uint256(auction.status()), 2); // Sold
        assertEq(token.balanceOf(buyer), TOKEN_AMOUNT);
    }

    function testBuySomeTokenSetsStatusSoldWhenAllBought2() public {
        uint256 first_amount = TOKEN_AMOUNT / 3;
        uint256 second_amount = TOKEN_AMOUNT - first_amount;

        uint256 first_price = auction.getCurrentPriceByAmount(first_amount);
        uint256 second_price = auction.getCurrentPriceByAmount(second_amount);

        vm.prank(buyer);
        auction.buySomeToken{value: first_price + 1}(first_amount);
        assertEq(uint256(auction.status()), 1); // still Active
        assertEq(auction.tokenAmount(), TOKEN_AMOUNT - first_amount);
        assertEq(token.balanceOf(buyer), first_amount);
        assertEq(address(auction).balance, 0);
        assertEq(address(buyer).balance, 100 ether - first_price);

        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 200 ether);
        vm.prank(buyer2);
        auction.buySomeToken{value: second_price + 1}(second_amount);
        assertEq(uint256(auction.status()), 2); // Sold
        assertEq(auction.tokenAmount(), 0);
        assertEq(token.balanceOf(buyer2), second_amount);
        assertEq(address(auction).balance, 0);
        assertEq(address(buyer2).balance, 200 ether - second_price);
    }

    function testBuySomeTokenThenBuyRemainingCorrectPrice() public {
        address buyer2 = makeAddr("buyer2");
        vm.deal(buyer2, 100 ether);

        uint256 firstBuyAmount = 60 ether;
        uint256 firstPrice = auction.getCurrentPriceByAmount(firstBuyAmount);

        vm.prank(buyer);
        auction.buySomeToken{value: firstPrice}(firstBuyAmount);

        // remaining = 40 ether, price should be proportional
        uint256 remainingAmount = auction.tokenAmount();
        uint256 remainingPrice = auction.getCurrentPriceByAmount(remainingAmount);

        uint256 seller2BalanceBefore = seller.balance;
        vm.prank(buyer2);
        auction.buy{value: remainingPrice}();

        assertEq(token.balanceOf(buyer2), remainingAmount);
        assertEq(seller.balance, seller2BalanceBefore + remainingPrice);
        assertEq(uint256(auction.status()), 2); // Sold
    }

    function testBuySomeTokenPriceConsistencyWithBuy() public {
        // buying all via buySomeToken should cost the same as buy()
        uint256 priceViaBuySome = auction.getCurrentPriceByAmount(TOKEN_AMOUNT);
        uint256 priceViaBuy = auction.getCurrentPriceByAmount(auction.tokenAmount());
        assertEq(priceViaBuySome, priceViaBuy);
    }

    function testBuySomeTokenRevertsIfInsufficientPayment() public {
        uint256 buyAmount = 40 ether;
        uint256 price = auction.getCurrentPriceByAmount(buyAmount);

        vm.prank(buyer);
        vm.expectRevert("Insufficient payment");
        auction.buySomeToken{value: price - 1}(buyAmount);
    }

    function testBuySomeTokenRevertsIfAmountExceedsAvailable() public {
        vm.prank(buyer);
        vm.expectRevert("Invalid amount");
        auction.buySomeToken{value: 100 ether}(TOKEN_AMOUNT + 1);
    }

    function testBuySomeTokenRevertsIfAmountIsZero() public {
        vm.prank(buyer);
        vm.expectRevert("Invalid amount");
        auction.buySomeToken{value: 1 ether}(0);
    }

}