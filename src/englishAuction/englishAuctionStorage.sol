// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EnglishAuctionStorage {
    enum AuctionStatus {
        Initialized,
        Active,
        Sold,
        Cancelled
    }

    event AuctionCreated(
        address indexed seller,
        uint256 tokenAmount,
        uint256 startPrice
    );
    event AuctionStarted(
        address indexed seller,
        address indexed token,
        uint256 startTime,
        uint256 expireTime
    );
    event AuctionBid(
        address indexed bidder,
        uint256 bidAmount
    );
    event AuctionWithdraw(address indexed bidder, uint256 amount);
    event AuctionSold(address indexed buyer, address indexed seller, uint256 price);
    event AuctionCancelled(address indexed seller);
    event AuctionReclaimed(address indexed seller);
    
    bool internal initialized;
    address public seller;
    IERC20 public token;
    uint256 public tokenAmount;
    uint256 public startPrice;
    uint256 public startTime;
    uint256 public expireTime;
    AuctionStatus public status;
    address public highestBidder;
    uint256 public highestBid;
    mapping(address => uint256) public pendingReturns;
    bool public antiSniping;
}