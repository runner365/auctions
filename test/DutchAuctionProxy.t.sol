// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";
import {DutchAuctionLogic} from "../src/dutchAuction/dutchAuctionLogic.sol";
import {DutchAuctionProxy} from "../src/dutchAuction/dutchAuctionProxy.sol";

contract DutchAuctionProxyTest is Test {
    DutchAuctionLogic internal logic;
    DutchAuctionProxy internal proxy;
    AuctionERC20 internal token;

    address internal seller;
    address internal buyer;

    uint256 internal constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 internal constant TOKEN_AMOUNT   = 100 ether;
    uint256 internal constant START_PRICE    = 10 ether;
    uint256 internal constant MIN_PRICE      = 1 ether;
    uint256 internal constant DURATION       = 1 days;

    function setUp() public {
        seller = makeAddr("seller");
        buyer  = makeAddr("buyer");

        vm.deal(buyer, 20 ether);

        token = new AuctionERC20("Dutch Token", "DUT", INITIAL_SUPPLY, seller);
        logic = new DutchAuctionLogic();

        vm.prank(seller);
        proxy = new DutchAuctionProxy(
            address(logic),
            TOKEN_AMOUNT,
            START_PRICE,
            MIN_PRICE,
            DURATION
        );
    }

    // ─── helpers ───────────────────────────────────────────────────────────────

    function _startAsSeller() internal {
        vm.startPrank(seller);
        token.approve(address(proxy), TOKEN_AMOUNT);
        proxy.start(address(token));
        vm.stopPrank();
    }

    // ─── start() ───────────────────────────────────────────────────────────────

    function testStartSetsActiveStatusAndMovesToken() public {
        _startAsSeller();

        assertEq(uint256(proxy.status()), 1); // Active
        assertEq(address(proxy.token()), address(token));
        assertEq(proxy.tokenAmount(), TOKEN_AMOUNT);

        // proxy holds the token, seller no longer has it
        assertEq(token.balanceOf(address(proxy)), TOKEN_AMOUNT);
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY - TOKEN_AMOUNT);

        // timing is set
        assertEq(proxy.expire_time(), proxy.start_time() + DURATION);
    }

    function testStartRevertsIfNotSeller() public {
        vm.startPrank(seller);
        token.approve(address(proxy), TOKEN_AMOUNT);
        vm.stopPrank();

        vm.prank(buyer);
        vm.expectRevert("Only seller can call this function");
        proxy.start(address(token));
    }

    function testStartRevertsIfAlreadyActive() public {
        _startAsSeller();

        vm.startPrank(seller);
        vm.expectRevert("Auction is already active");
        proxy.start(address(token));
        vm.stopPrank();
    }

    // ─── getCurrentPriceByAmount() ───────────────────────────────────────────────────────

    function testGetCurrentPriceAtStart() public {
        _startAsSeller();
        // right at start: no time elapsed, price should equal startPrice
        assertEq(proxy.getCurrentPriceByAmount(TOKEN_AMOUNT), START_PRICE);
    }

    function testGetCurrentPriceDecreasesMidway() public {
        _startAsSeller();

        vm.warp(proxy.start_time() + DURATION / 2);
        uint256 price = proxy.getCurrentPriceByAmount(TOKEN_AMOUNT);

        // midway price should be between min and start
        assertGt(price, MIN_PRICE);
        assertLt(price, START_PRICE);
        // expected: startPrice - (startPrice - minPrice) * 0.5
        uint256 expected = START_PRICE - (START_PRICE - MIN_PRICE) / 2;
        assertEq(price, expected);
    }

    function testGetCurrentPriceReturnsMinPriceAfterExpiry() public {
        _startAsSeller();
        vm.warp(proxy.expire_time() + 1);
        assertEq(proxy.getCurrentPriceByAmount(TOKEN_AMOUNT), MIN_PRICE);
    }

    function testGetCurrentPriceUsesProxyStorage() public {
        _startAsSeller();
        // logic contract storage is unmodified (proxy storage was set via delegatecall)
        assertEq(logic.startPrice(), 0);
        assertEq(proxy.startPrice(), START_PRICE);
    }

    // ─── buy() ─────────────────────────────────────────────────────────────────

    function testBuyAtStartPriceSetsStatusSoldAndTransfersToken() public {
        _startAsSeller();

        uint256 price = proxy.getCurrentPriceByAmount(TOKEN_AMOUNT); // == START_PRICE
        uint256 sellerBalanceBefore = seller.balance;

        vm.prank(buyer);
        proxy.buy{value: price}();

        // status becomes Sold (index 2)
        assertEq(uint256(proxy.status()), 2);

        // buyer receives the tokens
        assertEq(token.balanceOf(buyer), TOKEN_AMOUNT);
        assertEq(token.balanceOf(address(proxy)), 0);

        // seller receives the payment
        assertEq(seller.balance, sellerBalanceBefore + price);

        // proxy holds no ETH
        assertEq(address(proxy).balance, 0);
    }

    function testBuyRefundsExcessPayment() public {
        _startAsSeller();

        uint256 price = proxy.getCurrentPriceByAmount(TOKEN_AMOUNT);
        uint256 overpay = price + 3 ether;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        proxy.buy{value: overpay}();

        // buyer gets back the excess (only price is deducted)
        assertEq(buyer.balance, buyerBalanceBefore - price);
    }

    function testBuyRevertsIfInsufficientPayment() public {
        _startAsSeller();

        vm.prank(buyer);
        vm.expectRevert("Insufficient payment");
        proxy.buy{value: MIN_PRICE - 1}();
    }

    function testBuyRevertsAfterExpiry() public {
        _startAsSeller();
        vm.warp(proxy.expire_time() + 1);

        vm.prank(buyer);
        vm.expectRevert("Auction has expired");
        proxy.buy{value: MIN_PRICE}();
    }

    // ─── buySomeToken() ─────────────────────────────────────────────────────

    function testBuyWithAmountPartialPurchaseKeepsAuctionActive() public {
        _startAsSeller();

        uint256 amount = 40 ether;
        uint256 price = proxy.getCurrentPriceByAmount(amount);

        vm.prank(buyer);
        proxy.buySomeToken{value: price}(amount);

        assertEq(token.balanceOf(buyer), amount);
        assertEq(proxy.tokenAmount(), TOKEN_AMOUNT - amount);
        assertEq(uint256(proxy.status()), 1); // Active
        assertEq(address(proxy).balance, 0);
    }

    function testBuyWithAmountAllRemainingSetsSold() public {
        _startAsSeller();

        uint256 amount = TOKEN_AMOUNT;
        uint256 price = proxy.getCurrentPriceByAmount(amount);

        vm.prank(buyer);
        proxy.buySomeToken{value: price}(amount);

        assertEq(proxy.tokenAmount(), 0);
        assertEq(uint256(proxy.status()), 2); // Sold
        assertEq(token.balanceOf(buyer), TOKEN_AMOUNT);
    }

    function testBuyWithAmountRefundsExcessPayment() public {
        _startAsSeller();

        uint256 amount = 40 ether;
        uint256 price = proxy.getCurrentPriceByAmount(amount);
        uint256 overpay = price + 1 ether;
        uint256 buyerBalanceBefore = buyer.balance;

        vm.prank(buyer);
        proxy.buySomeToken{value: overpay}(amount);

        assertEq(buyer.balance, buyerBalanceBefore - price);
        assertEq(address(proxy).balance, 0);
    }

    function testBuyWithAmountRevertsIfInsufficientPayment() public {
        _startAsSeller();

        uint256 amount = 40 ether;
        uint256 price = proxy.getCurrentPriceByAmount(amount);
        
        vm.prank(buyer);
        vm.expectRevert("Insufficient payment");
        proxy.buySomeToken{value: price - 1}(amount);
    }

    function testBuyWithAmountRevertsIfAmountExceedsAvailable() public {
        _startAsSeller();

        vm.prank(buyer);
        vm.expectRevert("Not enough tokens left");
        // buyer has only 20 ether
        proxy.buySomeToken{value: 20 ether}(TOKEN_AMOUNT + 1);
    }

    // ─── withdraw() ────────────────────────────────────────────────────────────

    function testWithdrawAfterExpiryReturnsTokenToSeller() public {
        _startAsSeller();

        vm.warp(proxy.expire_time());

        vm.prank(seller);
        proxy.withdraw();

        // status becomes Expired (index 4)
        assertEq(uint256(proxy.status()), 4);

        // seller gets all tokens back
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testWithdrawRevertsBeforeExpiry() public {
        _startAsSeller();

        vm.expectRevert("Auction has not expired");
        vm.prank(seller);
        proxy.withdraw();
    }

    function testWithdrawRevertsIfNotSeller() public {
        _startAsSeller();
        vm.warp(proxy.expire_time());

        vm.prank(buyer);
        vm.expectRevert("Only seller can call this function");
        proxy.withdraw();
    }

    // ─── cancel() ──────────────────────────────────────────────────────────────

    function testCancelBeforeExpiryReturnsTokenToSeller() public {
        _startAsSeller();

        vm.prank(seller);
        proxy.cancel();

        // status becomes Cancelled (index 3)
        assertEq(uint256(proxy.status()), 3);

        // seller gets all tokens back
        assertEq(token.balanceOf(seller), INITIAL_SUPPLY);
        assertEq(token.balanceOf(address(proxy)), 0);
    }

    function testCancelRevertsAfterExpiry() public {
        _startAsSeller();
        vm.warp(proxy.expire_time() + 1);

        vm.expectRevert("Auction has expired");
        vm.prank(seller);
        proxy.cancel();
    }

    function testCancelRevertsIfNotSeller() public {
        _startAsSeller();

        vm.prank(buyer);
        vm.expectRevert("Only seller can call this function");
        proxy.cancel();
    }
}
