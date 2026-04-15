// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {EnglishAuction} from "../src/englishAuction.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";

contract EnglishAuctionTest is Test {
    EnglishAuction internal auction;
    AuctionERC20 internal token;

    address internal seller;
    address internal bidder1;
    address internal bidder2;

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant TOKEN_AMOUNT = 100 ether;
    uint256 internal constant START_PRICE = 1 ether;
    uint256 internal constant DURATION = 1 days;

    function setUp() public {
        seller = makeAddr("seller");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");

        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);

        vm.startPrank(seller);
        token = new AuctionERC20("Auction Token", "AUCT", INITIAL_SUPPLY, seller);
        auction = new EnglishAuction(TOKEN_AMOUNT, START_PRICE, true);

        token.approve(address(auction), TOKEN_AMOUNT);
        auction.startAuction(address(token), DURATION);
        vm.stopPrank();
    }

    function testReclaimAfterNoBidsReturnsTokens() public {
        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.reclaim();

        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(auction)), 0);
        assertEq(uint256(auction.status()), 3); // Cancelled
    }

    function testCancelAuctionRevertsWhenActiveBidExists() public {
        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.prank(seller);
        vm.expectRevert("Cannot cancel auction with active bids");
        auction.cancelAuction();
    }

    function testOutbidBidderCanWithdrawPendingReturns() public {
        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.prank(bidder2);
        auction.bid{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        auction.doneAuction();

        uint256 bidder1BalanceBefore = bidder1.balance;

        vm.prank(bidder1);
        auction.withdraw();

        assertEq(bidder1.balance, bidder1BalanceBefore + START_PRICE);
        assertEq(auction.pendingReturns(bidder1), 0);
    }

    function testDoneAuctionTransfersTokenAndPaysSeller() public {
        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(seller);
        auction.doneAuction();

        assertEq(token.balanceOf(bidder1), TOKEN_AMOUNT);
        assertEq(seller.balance, sellerBalanceBefore + 2 ether);
        assertEq(uint256(auction.status()), 2); // Sold
        assertEq(address(auction).balance, 0);
    }

    function testAntiSnipingExtendsByFiveMinutesWhenBidPlacedInLastFiveMinutes() public {
        uint256 originalExpireTime = auction.expire_time();

        // Move to the last 4 minutes 59 seconds of auction.
        vm.warp(originalExpireTime - 4 minutes - 59 seconds);

        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        uint256 expectedExpireTime = block.timestamp + 5 minutes;
        assertEq(auction.expire_time(), expectedExpireTime);
        assertGt(auction.expire_time(), originalExpireTime);
    }

    function testDoneAuctionRevertsBeforeExtendedExpireTime() public {
        uint256 originalExpireTime = auction.expire_time();

        // Trigger anti-sniping extension.
        vm.warp(originalExpireTime - 4 minutes - 59 seconds);
        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        // Still 1 second before the extended expiry.
        vm.warp(auction.expire_time() - 1);

        vm.prank(seller);
        vm.expectRevert("Auction has not expired");
        auction.doneAuction();

        // After extended expiry, settlement should succeed.
        vm.warp(auction.expire_time() + 1);
        vm.prank(seller);
        auction.doneAuction();

        assertEq(uint256(auction.status()), 2); // Sold
    }
}
