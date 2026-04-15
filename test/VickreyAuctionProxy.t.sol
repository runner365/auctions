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

        (/*bidHash*/,/*revealed*/,/*bidAmount*/,uint256 deposit,/*penaltyAmount*/,/*withdrawPenalized*/) = proxy.bids(bidder2);
        assertEq(deposit, 0);
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

    // ==================== withdrawButNotReveal Tests ====================

    function testWithdrawButNotRevealReturns50Percent() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");
        // bidder2 does NOT reveal

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        uint256 bidder2BalanceBefore = bidder2.balance;
        vm.prank(bidder2);
        proxy.withdrawButNotReveal();

        // bidder2 should receive 50% of deposit
        assertEq(bidder2.balance, bidder2BalanceBefore + 1.5 ether);
        
        // penaltyAmount should be set to 50%
        (/*bidHash*/,/*revealed*/,/*bidAmount*/,uint256 deposit,uint256 penaltyAmount,/*withdrawPenalized*/) = proxy.bids(bidder2);
        assertEq(penaltyAmount, 1.5 ether);
        assertEq(deposit, 1.5 ether); // remaining 50%
    }

    function testWithdrawButNotRevealOnlyNonWinner() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        // Winner (bidder1) cannot call withdrawButNotReveal
        vm.prank(bidder1);
        vm.expectRevert("Winner cannot call this function");
        proxy.withdrawButNotReveal();
    }

    function testWithdrawButNotRevealOnlyUnrevealedBids() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        // bidder2 revealed, so cannot use withdrawButNotReveal
        vm.prank(bidder2);
        vm.expectRevert("Bid already revealed");
        proxy.withdrawButNotReveal();
    }

    function testWithdrawButNotRevealCannotCallTwice() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");
        // bidder2 does NOT reveal

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        vm.prank(bidder2);
        proxy.withdrawButNotReveal();

        // Second call should revert
        vm.prank(bidder2);
        vm.expectRevert("Already withdrawn with penalty");
        proxy.withdrawButNotReveal();
    }

    function testWithdrawButNotRevealRevertsWhenNoDeposit() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        address bidder3 = makeAddr("bidder3");
        vm.prank(bidder3);
        vm.expectRevert("No bid committed");
        proxy.withdrawButNotReveal();
    }

    // ==================== claimOnBehalf Tests ====================

    function testClaimOnBehalfCollectsPenalties() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");
        bytes32 bidHash3 = _hashBid(2 ether, "b3-secret");

        address bidder3 = makeAddr("bidder3");
        vm.deal(bidder3, 10 ether);

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        vm.prank(bidder3);
        proxy.commitBid{value: 2 ether}(bidHash3);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");
        // bidder2 and bidder3 do NOT reveal

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        proxy.claimOnBehalf();

        // seller should receive penalties from bidder2 and bidder3
        // bidder2: 3 ether / 2 = 1.5 ether
        // bidder3: 2 ether / 2 = 1 ether
        // total: 2.5 ether
        assertEq(seller.balance, sellerBalanceBefore + 2.5 ether);
    }

    function testClaimOnBehalfOnlyBySeller() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        vm.prank(bidder1);
        vm.expectRevert("Only seller can call this function");
        proxy.claimOnBehalf();
    }

    function testClaimOnBehalfCannotCallTwice() public {
        _startAuctionAsSeller();
        _runTwoBidderFlow();

        vm.prank(seller);
        proxy.claimOnBehalf();

        // Second call should revert
        vm.prank(seller);
        vm.expectRevert("Already claimed on behalf of loser");
        proxy.claimOnBehalf();
    }

    // ==================== withdrawButNotReveal + claimOnBehalf Interaction Tests ====================

    function testWithdrawButNotRevealThenClaimOnBehalf() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");
        bytes32 bidHash3 = _hashBid(2 ether, "b3-secret");

        address bidder3 = makeAddr("bidder3");
        vm.deal(bidder3, 10 ether);

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        vm.prank(bidder3);
        proxy.commitBid{value: 2 ether}(bidHash3);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");
        // bidder2 and bidder3 do NOT reveal

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        // bidder2 calls withdrawButNotReveal first
        uint256 bidder2BalanceBefore = bidder2.balance;
        vm.prank(bidder2);
        proxy.withdrawButNotReveal();
        assertEq(bidder2.balance, bidder2BalanceBefore + 1.5 ether); // gets 50%

        // seller calls claimOnBehalf
        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        proxy.claimOnBehalf();

        // seller should receive:
        // - 50% penalty from bidder2 (remaining after bidder2 withdrew)
        // - 50% penalty from bidder3 (no prior withdrawal)
        // Total: 1.5 + 1 = 2.5 ether
        assertEq(seller.balance, sellerBalanceBefore + 2.5 ether);

        // Verify final states
        (/*bidHash*/,/*revealed*/,/*bidAmount*/,uint256 deposit,/*penaltyAmount*/,/*withdrawPenalized*/) = proxy.bids(bidder2);
        assertEq(deposit, 0); // bidder2's deposit fully consumed
    }

    function testClaimOnBehalfFirstThenWithdrawButNotReveal() public {
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(5 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(3 ether, "b2-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 5 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 3 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(5 ether, "b1-secret");
        // bidder2 does NOT reveal

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        // seller calls claimOnBehalf first
        uint256 sellerBalanceBefore = seller.balance;
        vm.prank(seller);
        proxy.claimOnBehalf();
        assertEq(seller.balance, sellerBalanceBefore + 1.5 ether); // gets 50%

        // bidder2 calls withdrawButNotReveal after
        uint256 bidder2BalanceBefore = bidder2.balance;
        vm.prank(bidder2);
        proxy.withdrawButNotReveal();
        
        // bidder2 should get remaining 50%
        assertEq(bidder2.balance, bidder2BalanceBefore + 1.5 ether);

        // Verify final states
        (/*bidHash*/,/*revealed*/,/*bidAmount*/,uint256 deposit,uint256 penaltyAmount,/*withdrawPenalized*/) = proxy.bids(bidder2);
        assertEq(deposit, 0); // deposit fully consumed
        assertEq(penaltyAmount, 1.5 ether); // penalty amount recorded
    }

    function testPenaltyAlwaysHalf() public {
        // Test that penalty is always 50% regardless of call order
        _startAuctionAsSeller();

        bytes32 bidHash1 = _hashBid(6 ether, "b1-secret");
        bytes32 bidHash2 = _hashBid(4 ether, "b2-secret");

        vm.prank(bidder1);
        proxy.commitBid{value: 6 ether}(bidHash1);

        vm.prank(bidder2);
        proxy.commitBid{value: 4 ether}(bidHash2);

        _moveToRevealPhase();

        vm.prank(bidder1);
        proxy.revealBid(6 ether, "b1-secret");

        _moveToEndPhase();

        vm.prank(bidder1);
        proxy.endAuction();

        uint256 bidder2BalanceBefore = bidder2.balance;
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(bidder2);
        proxy.withdrawButNotReveal();

        vm.prank(seller);
        proxy.claimOnBehalf();

        // bidder2 gets 50%, seller gets 50%
        assertEq(bidder2.balance, bidder2BalanceBefore + 2 ether); // 4 * 0.5
        assertEq(seller.balance, sellerBalanceBefore + 2 ether); // 4 * 0.5
    }
}
