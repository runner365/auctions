// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VickreyAuction} from "../src/vickreyAuction.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";

contract VickreyAuctionTest is Test {
    VickreyAuction internal auction;
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

        vm.startPrank(seller);
        token = new AuctionERC20("Auction Token", "AUCT", INITIAL_SUPPLY, seller);
        auction = new VickreyAuction(START_PRICE, COMMIT_DURATION, REVEAL_DURATION, END_DURATION);

        token.approve(address(auction), TOKEN_AMOUNT);
        auction.startAuction(address(token), TOKEN_AMOUNT);
        vm.stopPrank();
    }

    function _hashBid(uint256 amount, string memory secret) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(amount, secret));
    }

    function _moveToRevealPhase() internal {
        vm.warp(auction.commitEndTime() + 1);
    }

    function _moveToEndPhase() internal {
        vm.warp(auction.revealEndTime() + 1);
    }

    function testStartAuctionTransfersTokenAndSetsStatus() public view {
        assertEq(token.balanceOf(address(auction)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);
        assertEq(uint256(auction.status()), 1); // Committing
    }

    function testCommitTwiceReverts() public {
        bytes32 bidHash = _hashBid(2 ether, "s1");

        vm.prank(bidder1);
        auction.commitBid{value: 2 ether}(bidHash);

        vm.prank(bidder1);
        vm.expectRevert("Bid already committed");
        auction.commitBid{value: 2 ether}(bidHash);
    }

    function testRevealWithWrongSecretReverts() public {
        bytes32 bidHash = _hashBid(3 ether, "secret");

        vm.prank(bidder1);
        auction.commitBid{value: 3 ether}(bidHash);

        _moveToRevealPhase();

        vm.prank(bidder1);
        vm.expectRevert("Invalid bid reveal");
        auction.revealBid(3 ether, "wrong-secret");
    }

    function testFullFlowSecondPricePayoutAndWithdrawals() public {
        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");

        vm.prank(bidder1);
        auction.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        auction.commitBid{value: 3 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        auction.revealBid(5 ether, "b1-secret");

        vm.prank(bidder2);
        auction.revealBid(3 ether, "b2-secret");

        _moveToEndPhase();

        vm.prank(bidder1);
        auction.endAuction();

        assertEq(auction.highestBidder(), bidder1);
        assertEq(auction.highestBid(), 5 ether);
        assertEq(auction.secondHighestBid(), 3 ether);
        assertEq(auction.bid4Seller(), 3 ether);
        assertEq(uint256(auction.status()), 3); // EndAuctioned

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        auction.withdrawFund();
        assertEq(seller.balance, sellerBalanceBefore + 3 ether);

        uint256 winnerBalanceBeforeClaim = bidder1.balance;
        vm.prank(bidder1);
        auction.claim();
        assertEq(token.balanceOf(bidder1), TOKEN_AMOUNT);
        assertEq(bidder1.balance, winnerBalanceBeforeClaim + 2 ether);

        uint256 loserBalanceBeforeWithdraw = bidder2.balance;
        vm.prank(bidder2);
        auction.withdraw();
        assertEq(bidder2.balance, loserBalanceBeforeWithdraw + 3 ether);
    }

    function testWinnerCannotCallWithdraw() public {
        bytes32 bidHash1 = _hashBid(4 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(2 ether, "b2-secret");

        vm.prank(bidder1);
        auction.commitBid{value: 4 ether}(bidHash1);

        vm.prank(bidder2);
        auction.commitBid{value: 2 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        auction.revealBid(4 ether, "b1-secret");

        vm.prank(bidder2);
        auction.revealBid(2 ether, "b2-secret");

        _moveToEndPhase();

        vm.prank(bidder2);
        auction.endAuction();

        vm.prank(bidder1);
        vm.expectRevert("Only non-winners can withdraw");
        auction.withdraw();
    }
}