// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";
import {VickreyAuctionLogic} from "../src/vickreyAuction/vickreyAuctionLogic.sol";
import {VickreyAuctionProxy} from "../src/vickreyAuction/vickreyAuctionProxy.sol";

contract VickreyAuctionProxyTest is Test {
    VickreyAuctionLogic internal logic;
    VickreyAuctionProxy internal proxy;
    AuctionERC20 internal token;

    address internal seller;
    address internal bidder1;
    address internal bidder2;

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant TOKEN_AMOUNT = 100 ether;
    uint256 internal constant START_PRICE = 1 ether;
    uint256 internal constant COMMIT_DURATION = 1 days;
    uint256 internal constant REVEAL_DURATION = 1 days;
    uint256 internal constant END_DURATION = 1 days;

    function setUp() public {
        seller = makeAddr("seller");
        bidder1 = makeAddr("bidder1");
        bidder2 = makeAddr("bidder2");

        vm.deal(bidder1, 10 ether);
        vm.deal(bidder2, 10 ether);

        token = new AuctionERC20("Auction Token", "AUCT", INITIAL_SUPPLY, seller);
        logic = new VickreyAuctionLogic();

        vm.prank(seller);
        proxy = new VickreyAuctionProxy(
            address(logic),
            START_PRICE,
            COMMIT_DURATION,
            REVEAL_DURATION,
            END_DURATION
        );
    }

    function _hashBid(uint256 amount, string memory secret) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(amount, secret));
    }

    function _startAuctionAsSeller() internal {
        vm.startPrank(seller);
        token.approve(address(proxy), TOKEN_AMOUNT);
        proxy.startAuction(address(token), TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function _moveToRevealPhase() internal {
        vm.warp(proxy.commitEndTime() + 1);
    }

    function _moveToEndPhase() internal {
        vm.warp(proxy.revealEndTime() + 1);
    }

    function _runTwoBidderFlow() internal {
        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");

        vm.prank(bidder2);
        proxy.revealBid(3 ether, "b2-secret");

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();
    }

    function testStartAuctionSetsStateAndTokenOwnership() public {
        _startAuctionAsSeller();

        assertEq(uint256(proxy.status()), 1); // Committing
        assertEq(address(proxy.token()), address(token));
        assertEq(proxy.tokenAmount(), TOKEN_AMOUNT);

        assertEq(token.balanceOf(address(proxy)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);
    }

    function testStartAuctionRevertsWhenNotSeller() public {
        vm.prank(bidder1);
        vm.expectRevert("Only seller can call this function");
        proxy.startAuction(address(token), TOKEN_AMOUNT);
    }

    function testCommitAndRevealUpdateBids() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(4 ether, "s1");
        bytes32 bidHash2 = _hashBid(2 ether, "s2");

        vm.prank(bidder1);
        proxy.commitBid{value: 4 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 2 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(4 ether, "s1");

        vm.prank(bidder2);
        proxy.revealBid(2 ether, "s2");

        assertEq(uint256(proxy.status()), 2); // Revealing
        assertEq(proxy.highestBid(), 4 ether);
        assertEq(proxy.secondHighestBid(), 2 ether);
        assertEq(proxy.highestBidder(), bidder1);
    }

    function testEndAuctionSetsEndStatusAndSellerReceivableBid() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        assertEq(uint256(proxy.status()), 3); // EndAuctioned
        assertEq(proxy.highestBid(), 5 ether);
        assertEq(proxy.secondHighestBid(), 3 ether);
        assertEq(proxy.bid4Seller(), 3 ether);
    }

    function testWithdrawFundPaysSellerSecondPrice() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(seller);
        proxy.withdrawFund();

        assertEq(seller.balance, sellerBalanceBefore + 3 ether);
        assertEq(proxy.bid4Seller(), 0);
        assertEq(proxy.sellerWithdrawn(), true);
    }

    function testClaimTransfersTokenAndRefundsWinnerExcess() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        vm.prank(seller);
        proxy.withdrawFund();

        uint256 winnerBalanceBefore = bidder1.balance;

        vm.prank(bidder1);
        proxy.claim();

        assertEq(token.balanceOf(bidder1), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(proxy)), 0);
        assertEq(proxy.tokenAmount(), 0);

        // winner deposited 5 ether, paid second price 3 ether, refunded 2 ether
        assertEq(bidder1.balance, winnerBalanceBefore + 2 ether);
    }

    function testWithdrawRefundsLoserDeposit() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        uint256 loserBalanceBefore = bidder2.balance;

        vm.prank(bidder2);
        proxy.withdraw();

        assertEq(bidder2.balance, loserBalanceBefore + 3 ether);

        (,,, uint256 depositAfter) = proxy.bids(bidder2);
        assertEq(depositAfter, 0);
    }

    function testWithdrawRevertsForWinner() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        vm.prank(bidder1);
        vm.expectRevert("Only non-winners can withdraw");
        proxy.withdraw();
    }

    function testClaimRevertsForNonWinner() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        vm.prank(bidder2);
        vm.expectRevert("Only winner can claim");
        proxy.claim();
    }
}
