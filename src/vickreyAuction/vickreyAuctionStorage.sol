// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VickreyAuctionStorage is ReentrancyGuard {
    using SafeERC20 for IERC20;
    enum AuctionStatus {
        Initialized,
        Committing, 
        Revealing, 
        EndAuctioned,
        EndPhasedOut
    }

    struct Bid {
        bytes32 bidHash;
        bool revealed;
        uint256 bidAmount;
        uint256 deposit;
        uint256 penaltyAmount;
        bool withdrawPenalized;
    }

    mapping(address => Bid) public bids;
    address[] public bidders;
    AuctionStatus public status;

    address public seller;
    uint256 public startPrice;

    uint256 public commitDuration;
    uint256 public revealDuration;
    uint256 public endDuration;

    uint256 public commitEndTime;
    uint256 public revealEndTime;
    uint256 public endEndTime;
    uint256 public highestBid;
    address public highestBidder;
    uint256 public secondHighestBid;
    uint256 public bid4Seller;
    bool public sellerWithdrawn;
    
    IERC20 public token;
    uint256 public tokenAmount;

    bool internal claimedPenaltyDone;
    uint256 public claimOnBehalfOffset;

    event AuctionStarted(address indexed _seller, 
                        address indexed _token, 
                        uint256 _tokenAmount,
                        uint256 _startPrice,
                        uint256 _startTime, 
                        uint256 _commitEndTime, 
                        uint256 _revealEndTime, 
                        uint256 _endEndTime);

    event BidCommitted(address indexed bidder);
    event BidRevealed(address indexed bidder, uint256 bidAmount);
    event AuctionEnded(address indexed winner, uint256 winningBid, uint256 secondHighestBid);

    event PenaltyClaimed(address indexed bidder, uint256 penaltyAmount);
    event BidPenalized(address indexed bidder, uint256 penaltyAmount, uint256 notRevealdCount);

    event SellerChanged(address indexed oldSeller, address indexed newSeller);
}