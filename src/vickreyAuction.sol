// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract VickreyAuction is ReentrancyGuard {
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
    }

    mapping(address => Bid) public bids;
    AuctionStatus public status;

    address public immutable SELLER;
    uint256 public immutable START_PRICE;

    uint256 public immutable COMMIT_DURATION;
    uint256 public immutable REVEAL_DURATION;
    uint256 public immutable END_DURATION;

    uint256 public commitEndTime;
    uint256 public revealEndTime;
    uint256 public endEndTime;
    uint256 public highestBid;
    address public highestBidder;
    uint256 public secondHighestBid;
    uint256 public bid4Seller;
    bool private sellerWithdrawn;
    
    IERC20 public token;
    uint256 public tokenAmount;

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

    constructor(
        uint256 _startPrice,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _endDuration
    ) {
        require(_startPrice > 0, "start price must be greater than 0");
        require(_commitDuration > 0, "Commit duration must be greater than 0");
        require(_revealDuration > 0, "Reveal duration must be greater than 0");
        require(_endDuration > 0, "End duration must be greater than 0");
        status = AuctionStatus.Initialized;
        
        START_PRICE = _startPrice;

        highestBid = 0;
        secondHighestBid = 0;
        highestBidder = address(0);
        bid4Seller = 0;
        sellerWithdrawn = false;

        COMMIT_DURATION = _commitDuration;
        REVEAL_DURATION = _revealDuration;
        END_DURATION = _endDuration;

        SELLER = msg.sender;
    }

    modifier onlySeller() {
        require(msg.sender == SELLER, "Only seller can call this function");
        _;
    }
    modifier inStatus(AuctionStatus _status) {
        /*
        enum AuctionStatus {
            Initialized,
            Committing, 
            Revealing, 
            EndAuctioned,
            EndPhasedOut
        }
        */
        if (_status == AuctionStatus.Committing) {
            require(block.timestamp < commitEndTime, "Commit phase ended");
        } else if (_status == AuctionStatus.Revealing) {
            require(block.timestamp >= commitEndTime, "Not more than commit end time");
            require(block.timestamp < revealEndTime, "Not in reveal phase");
        } else if (_status == AuctionStatus.EndAuctioned) {
            require(block.timestamp >= revealEndTime, "Not in ended phase");
            require(block.timestamp < endEndTime, "Not more than end end time");
        } else if (_status == AuctionStatus.EndPhasedOut) {
            require(block.timestamp >= endEndTime, "Not in end phased out phase");
        } else {
            revert("Invalid auction status");
        }
        _;
    }

    function startAuction(address _token, uint256 _tokenAmount) external onlySeller {
        require(status == AuctionStatus.Initialized, "Auction already started");
        require(_token != address(0), "Invalid token address");
        require(_tokenAmount > 0, "Token amount must be greater than 0");

        status = AuctionStatus.Committing;

        token = IERC20(_token);
        tokenAmount = _tokenAmount;
        commitEndTime = block.timestamp + COMMIT_DURATION;
        revealEndTime = commitEndTime + REVEAL_DURATION;
        endEndTime = revealEndTime + END_DURATION; // End phase lasts for END_DURATION seconds

        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        emit AuctionStarted(msg.sender, _token, _tokenAmount, START_PRICE, block.timestamp, commitEndTime, revealEndTime, endEndTime);
    }

    function commitBid(bytes32 _bidHash) external payable nonReentrant inStatus(AuctionStatus.Committing) {
        require(status == AuctionStatus.Committing, "Auction not in commit phase");
        require(bids[msg.sender].bidHash == bytes32(0), "Bid already committed");

        bids[msg.sender] = Bid({
            bidHash: _bidHash,
            revealed: false,
            bidAmount: 0,
            deposit: msg.value
        });

        emit BidCommitted(msg.sender);
    }

    function revealBid(uint256 _bidAmount, string calldata _secret) external nonReentrant inStatus(AuctionStatus.Revealing) {
        status = AuctionStatus.Revealing;

        Bid storage bid = bids[msg.sender];
        
        require(bid.bidHash != bytes32(0), "No bid committed");
        require(!bid.revealed, "Bid already revealed");
        require(keccak256(abi.encodePacked(_bidAmount, _secret)) == bid.bidHash, "Invalid bid reveal");
        require(_bidAmount >= START_PRICE, "Bid amount must be greater than start price");
        require(bid.deposit >= _bidAmount, "Deposit must cover bid amount");
        
        bid.revealed = true;
        bid.bidAmount = _bidAmount;

        if (_bidAmount > highestBid) {
            secondHighestBid = highestBid;
            highestBid = _bidAmount;
            highestBidder = msg.sender;
        } else if (_bidAmount > secondHighestBid) {
            secondHighestBid = _bidAmount;
        }

        emit BidRevealed(msg.sender, _bidAmount);
    }

    function endAuction() external nonReentrant inStatus(AuctionStatus.EndAuctioned) {
        require(status == AuctionStatus.Revealing, "Auction not in reveal phase");
        status = AuctionStatus.EndAuctioned;

        if (secondHighestBid > 0) {
            bid4Seller = secondHighestBid;
        } else {
            bid4Seller = highestBid;
        }
        emit AuctionEnded(highestBidder, highestBid, secondHighestBid);
    }

    // seller can withdraw the winning bid amount, loser can withdraw their deposit after auction ended
    function withdrawFund() external nonReentrant onlySeller inStatus(AuctionStatus.EndAuctioned) {
        require(status == AuctionStatus.EndAuctioned, "Auction not ended yet");
        require(!sellerWithdrawn, "Already withdrawn");
        require(bid4Seller > 0, "No winning bid to claim");
        sellerWithdrawn = true;
        uint256 amount = bid4Seller;
        bid4Seller = 0; // Prevent re-entrancy

        (bool sent, ) = payable(SELLER).call{value: amount}("");
        require(sent, "Failed to pay seller");
    }

    // loser can withdraw their deposit, winner can claim the token and refund excess deposit if any
    function withdraw() external nonReentrant inStatus(AuctionStatus.EndAuctioned) {
        require(status == AuctionStatus.EndAuctioned, "Auction not ended yet");
        require(msg.sender != highestBidder, "Only non-winners can withdraw");

        Bid storage bid = bids[msg.sender];
        require(bid.bidHash != bytes32(0), "No bid committed");
        require(bid.revealed, "Bid not revealed");
        require(bid.deposit > 0, "No deposit to withdraw");

        uint256 refundAmount = bid.deposit;

        bid.deposit = 0; // Prevent re-entrancy
        if (refundAmount > 0) {
            (bool sent, ) = payable(msg.sender).call{value: refundAmount}("");
            require(sent, "Failed to refund deposit");
        }
    }

    // Winner can claim the token and refund excess deposit if any
    function claim() external nonReentrant {
        require(status == AuctionStatus.EndAuctioned, "Auction not ended yet");
        require(msg.sender == highestBidder, "Only winner can claim");

        Bid storage bid = bids[msg.sender];
        require(bid.bidHash != bytes32(0), "No bid committed");
        require(bid.revealed, "Bid not revealed");
        require(tokenAmount > 0, "No tokens to claim");
        uint256 _tokenAmount = tokenAmount;
        tokenAmount = 0;
        
        token.safeTransfer(msg.sender, _tokenAmount);
        

        uint256 finalPrice = secondHighestBid > 0 ? secondHighestBid : highestBid;
        uint256 refundAmount = bid.deposit - finalPrice;

        if (refundAmount > 0) {
            (bool sent, ) = payable(msg.sender).call{value: refundAmount}("");
            require(sent, "Failed to refund excess deposit");
        }
    }
}
