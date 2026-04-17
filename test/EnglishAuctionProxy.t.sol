// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";
import {EnglishAuctionLogic} from "../src/englishAuction/englishAuctionLogic.sol";
import {EnglishAuctionProxy} from "../src/englishAuction/englishAuctionProxy.sol";

contract EnglishAuctionProxyTest is Test {
    EnglishAuctionProxy internal proxy;
    EnglishAuctionLogic internal auction;
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
        proxy = new EnglishAuctionProxy(
            address(new EnglishAuctionLogic()),
            abi.encodeCall(
                EnglishAuctionLogic.initialize,
                (TOKEN_AMOUNT, START_PRICE, true)
            )
        );
        auction = EnglishAuctionLogic(address(proxy));
        vm.stopPrank();
    }

    function _startAuctionAsSeller() internal {
        vm.startPrank(seller);
        token.approve(address(auction), TOKEN_AMOUNT);
        auction.startAuction(address(token), DURATION);
        vm.stopPrank();
    }

    function testStartAuctionSetsStateAndMovesToken() public {
        _startAuctionAsSeller();

        assertEq(uint256(auction.status()), 1); // Active
        assertEq(address(auction.token()), address(token));
        assertEq(auction.tokenAmount(), TOKEN_AMOUNT);
        assertEq(auction.startPrice(), START_PRICE);
        assertEq(token.balanceOf(address(auction)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);
        assertEq(auction.expireTime(), auction.startTime() + DURATION);
    }

    function testBidTracksHighestBidAndPendingReturns() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.prank(bidder2);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBidder(), bidder2);
        assertEq(auction.highestBid(), 2 ether);
        assertEq(auction.pendingReturns(bidder1), START_PRICE);
    }

    function testWithdrawRevertsBeforeAuctionEnds() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.prank(bidder2);
        auction.bid{value: 2 ether}();

        vm.prank(bidder1);
        vm.expectRevert("Auction is not ended yet");
        auction.withdraw();
    }

    function testWithdrawWorksAfterDoneAuctionForOutbidBidder() public {
        _startAuctionAsSeller();

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
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        auction.doneAuction();

        assertEq(uint256(auction.status()), 2); // Sold
        assertEq(token.balanceOf(bidder1), TOKEN_AMOUNT);
        assertEq(seller.balance, sellerBalanceBefore + 2 ether);
        assertEq(address(proxy).balance, 0);
    }

    function testReclaimWhenNoBidCancelsAndReturnsToken() public {
        _startAuctionAsSeller();

        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(seller);
        auction.reclaim();

        assertEq(uint256(auction.status()), 3); // Cancelled
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
    }

    function testReclaimRevertsWhenThereIsBid() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(seller);
        vm.expectRevert("Cannot reclaim with active bid");
        auction.reclaim();
    }

    function testCancelAuctionWhenNoBidCancelsAndReturnsToken() public {
        _startAuctionAsSeller();

        vm.prank(seller);
        auction.cancelAuction();

        assertEq(uint256(auction.status()), 3); // Cancelled
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
    }

    function testCancelAuctionRevertsWhenBidExists() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: START_PRICE}();

        vm.prank(seller);
        vm.expectRevert("Cannot cancel auction with active bids");
        auction.cancelAuction();
    }

    function testGetCurrentPriceLifecycle() public {
        _startAuctionAsSeller();

        assertEq(auction.getCurrentPrice(), START_PRICE);

        vm.prank(bidder1);
        auction.bid{value: 2 ether}();
        assertEq(auction.getCurrentPrice(), 2 ether);

        vm.warp(block.timestamp + DURATION + 1);
        assertEq(auction.getCurrentPrice(), 0);
    }

    function testGetCurrentPriceUsesProxyStorageContext() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        assertEq(auction.highestBid(), 2 ether);
        // Logic contract storage is separate from proxy storage, would be 0
    }

    function testAntiSnipingExtendsByFiveMinutesWhenBidInLastFiveMinutes() public {
        _startAuctionAsSeller();

        uint256 originalExpireTime = auction.expireTime();

        // Move into the last 4m59s and place a bid.
        vm.warp(originalExpireTime - 4 minutes - 59 seconds);
        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        uint256 expectedExpireTime = block.timestamp + 5 minutes;
        assertEq(auction.expireTime(), expectedExpireTime);
        assertGt(auction.expireTime(), originalExpireTime);
    }

    function testDoneAuctionRevertsBeforeExtendedExpireTime() public {
        _startAuctionAsSeller();

        uint256 originalExpireTime = auction.expireTime();

        // Trigger extension in the last 5 minutes.
        vm.warp(originalExpireTime - 4 minutes - 59 seconds);
        vm.prank(bidder1);
        auction.bid{value: 2 ether}();

        // Still before the extended deadline.
        vm.warp(auction.expireTime() - 1);
        vm.prank(seller);
        vm.expectRevert("Auction has not expired");
        auction.doneAuction();

        // After extended deadline, auction can be settled.
        vm.warp(auction.expireTime() + 1);
        vm.prank(seller);
        auction.doneAuction();

        assertEq(uint256(auction.status()), 2); // Sold
    }
}
