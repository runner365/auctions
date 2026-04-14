// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";
import {EnglishAuctionLogic} from "../src/englishAuction/englishAuctionLogic.sol";
import {EnglishAuctionProxy} from "../src/englishAuction/englishAuctionProxy.sol";

contract EnglishAuctionProxyTest is Test {
    EnglishAuctionLogic internal logic;
    EnglishAuctionProxy internal proxy;
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

        token = new AuctionERC20("Auction Token", "AUCT", INITIAL_SUPPLY, seller);
        logic = new EnglishAuctionLogic();
        proxy = new EnglishAuctionProxy(address(logic), TOKEN_AMOUNT, START_PRICE);
    }

    function _startAuctionAsSeller() internal {
        vm.startPrank(seller);
        token.approve(address(proxy), TOKEN_AMOUNT);
        proxy.startAuction(address(token), DURATION);
        vm.stopPrank();
    }

    function testStartAuctionSetsStateAndMovesToken() public {
        _startAuctionAsSeller();

        assertEq(uint256(proxy.status()), 1); // Active
        assertEq(address(proxy.token()), address(token));
        assertEq(proxy.tokenAmount(), TOKEN_AMOUNT);
        assertEq(proxy.startPrice(), START_PRICE);
        assertEq(token.balanceOf(address(proxy)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);
        assertEq(proxy.expireTime(), proxy.startTime() + DURATION);
    }

    function testBidTracksHighestBidAndPendingReturns() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: START_PRICE}();

        vm.prank(bidder2);
        proxy.bid{value: 2 ether}();

        assertEq(proxy.highestBidder(), bidder2);
        assertEq(proxy.highestBid(), 2 ether);
        assertEq(proxy.pendingReturns(bidder1), START_PRICE);
    }

    function testWithdrawRevertsBeforeAuctionEnds() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: START_PRICE}();

        vm.prank(bidder2);
        proxy.bid{value: 2 ether}();

        vm.prank(bidder1);
        vm.expectRevert("Auction is not ended yet");
        proxy.withdraw();
    }

    function testWithdrawWorksAfterDoneAuctionForOutbidBidder() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: START_PRICE}();

        vm.prank(bidder2);
        proxy.bid{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        vm.prank(seller);
        proxy.doneAuction();

        uint256 bidder1BalanceBefore = bidder1.balance;
        vm.prank(bidder1);
        proxy.withdraw();

        assertEq(bidder1.balance, bidder1BalanceBefore + START_PRICE);
        assertEq(proxy.pendingReturns(bidder1), 0);
    }

    function testDoneAuctionTransfersTokenAndPaysSeller() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: 2 ether}();

        vm.warp(block.timestamp + DURATION + 1);

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        proxy.doneAuction();

        assertEq(uint256(proxy.status()), 2); // Sold
        assertEq(token.balanceOf(bidder1), TOKEN_AMOUNT);
        assertEq(seller.balance, sellerBalanceBefore + 2 ether);
        assertEq(address(proxy).balance, 0);
    }

    function testReclaimWhenNoBidCancelsAndReturnsToken() public {
        _startAuctionAsSeller();

        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(seller);
        proxy.reclaim();

        assertEq(uint256(proxy.status()), 3); // Cancelled
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
    }

    function testReclaimRevertsWhenThereIsBid() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: START_PRICE}();

        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(seller);
        vm.expectRevert("Cannot reclaim with active bid");
        proxy.reclaim();
    }

    function testCancelAuctionWhenNoBidCancelsAndReturnsToken() public {
        _startAuctionAsSeller();

        vm.prank(seller);
        proxy.cancelAuction();

        assertEq(uint256(proxy.status()), 3); // Cancelled
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
    }

    function testCancelAuctionRevertsWhenBidExists() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: START_PRICE}();

        vm.prank(seller);
        vm.expectRevert("Cannot cancel auction with active bids");
        proxy.cancelAuction();
    }

    function testGetCurrentPriceLifecycle() public {
        _startAuctionAsSeller();

        assertEq(proxy.getCurrentPrice(), START_PRICE);

        vm.prank(bidder1);
        proxy.bid{value: 2 ether}();
        assertEq(proxy.getCurrentPrice(), 2 ether);

        vm.warp(block.timestamp + DURATION + 1);
        assertEq(proxy.getCurrentPrice(), 0);
    }

    function testGetCurrentPriceUsesProxyStorageContext() public {
        _startAuctionAsSeller();

        vm.prank(bidder1);
        proxy.bid{value: 2 ether}();

        assertEq(proxy.highestBid(), 2 ether);
        assertEq(logic.highestBid(), 0);
    }

    function testGetCurrentPriceDelegateRevertsForExternalCall() public {
        vm.expectRevert("Only self call");
        proxy.getCurrentPriceDelegate();
    }
}
