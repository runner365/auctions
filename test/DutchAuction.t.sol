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

        uint256 currentPrice = auction.getCurrentPrice();
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
}