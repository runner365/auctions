// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {VickreyAuctionStorage} from "./vickreyAuctionStorage.sol";

contract VickreyAuctionLogic is Initializable, UUPSUpgradeable, OwnableUpgradeable,ReentrancyGuard, VickreyAuctionStorage {
    using SafeERC20 for IERC20;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        uint256 _startPrice,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _endDuration
    ) external initializer {
        require(_startPrice > 0, "start price must be greater than 0");
        require(_commitDuration > 0, "Commit duration must be greater than 0");
        require(_revealDuration > 0, "Reveal duration must be greater than 0");
        require(_endDuration > 0, "End duration must be greater than 0");
        __Ownable_init(msg.sender);
        status = AuctionStatus.Initialized;
        seller = msg.sender;
        
        startPrice = _startPrice;

        highestBid = 0;
        secondHighestBid = 0;
        highestBidder = address(0);
        bid4Seller = 0;
        sellerWithdrawn = false;
        claimedPenaltyDone = false;
        claimOnBehalfOffset = 0;

        commitDuration = _commitDuration;
        revealDuration = _revealDuration;
        endDuration = _endDuration;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        require(newImplementation != address(0), "Invalid implementation");
    }

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function");
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
        commitEndTime = block.timestamp + commitDuration;
        revealEndTime = commitEndTime + revealDuration;
        endEndTime = revealEndTime + endDuration; // End phase lasts for endDuration seconds

        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        emit AuctionStarted(msg.sender, _token, _tokenAmount, startPrice, block.timestamp, commitEndTime, revealEndTime, endEndTime);
    }

    function commitBid(bytes32 _bidHash) external payable nonReentrant inStatus(AuctionStatus.Committing) {
        require(status == AuctionStatus.Committing, "Auction not in commit phase");
        require(bids[msg.sender].bidHash == bytes32(0), "Bid already committed");

        bids[msg.sender] = Bid({
            bidHash: _bidHash,
            revealed: false,
            bidAmount: 0,
            deposit: msg.value,
            penaltyAmount: 0,
            withdrawPenalized: false
        });
        bidders.push(msg.sender);
        emit BidCommitted(msg.sender);
    }

    function revealBid(uint256 _bidAmount, string calldata _secret) external nonReentrant inStatus(AuctionStatus.Revealing) {
        status = AuctionStatus.Revealing;

        Bid storage bid = bids[msg.sender];
        
        require(bid.bidHash != bytes32(0), "No bid committed");
        require(!bid.revealed, "Bid already revealed");
        require(keccak256(abi.encodePacked(_bidAmount, _secret)) == bid.bidHash, "Invalid bid reveal");
        require(_bidAmount >= startPrice, "Bid amount must be greater than start price");
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

        (bool sent, ) = payable(seller).call{value: amount}("");
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

    // loser can withdraw their deposit with penalty if they did not reveal their bid before the end of the auction, winner can claim the token and refund excess deposit if any
    function withdrawButNotReveal() external nonReentrant inStatus(AuctionStatus.EndAuctioned) {
        require(status == AuctionStatus.EndAuctioned, "Auction not ended yet");
        require(msg.sender != highestBidder, "Winner cannot call this function");

        Bid storage bid = bids[msg.sender];
        require(bid.bidHash != bytes32(0), "No bid committed");
        require(!bid.revealed, "Bid already revealed");
        require(bid.deposit > 0, "No deposit to withdraw");
        require(!bid.withdrawPenalized, "Already withdrawn with penalty");
        bid.withdrawPenalized = true;
        
        uint256 refundAmount = 0;
        if (bid.penaltyAmount == 0) {
            bid.penaltyAmount = bid.deposit / 2; // Penalize 50% of the deposit
            refundAmount = bid.deposit - bid.penaltyAmount; // Refund the rest to the bidder
        } else {
            refundAmount = bid.deposit;
        }
        bid.deposit -= refundAmount; // Prevent re-entrancy and double claiming of penalty
        if (refundAmount > 0) {
            (bool sent, ) = payable(msg.sender).call{value: refundAmount}("");
            require(sent, "Failed to refund deposit");

            emit PenaltyClaimed(msg.sender, refundAmount);
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

    // punish the bidder who did not reveal their bid before the end of the auction,
    // let the seller claim the half of the deposit as penalty, and the rest of the deposit will be refunded to the bidder
    function claimOnBehalf(uint256 amountOnce) external nonReentrant onlySeller inStatus(AuctionStatus.EndAuctioned) {
        require(status == AuctionStatus.EndAuctioned, "Auction not ended yet");
        require(!claimedPenaltyDone, "Already claimed on behalf of loser");
        require(bidders.length > 0, "No bids placed");
        require(amountOnce > 0, "Invalid amountOnce");
        require(claimOnBehalfOffset < bidders.length, "All bidders have been processed");
        
        uint256 leftAmount = bidders.length - claimOnBehalfOffset;
        uint256 totalAmount = amountOnce > leftAmount ? leftAmount : amountOnce;

        uint256 penaltyAmount = 0;
        uint256 notRevealdCount = 0;

        for (uint256 i = 0; i < totalAmount; i++) {
            address bidAddress = bidders[claimOnBehalfOffset + i];
            Bid storage bid = bids[bidAddress];
            if (bid.bidHash != bytes32(0) && !bid.revealed && bid.deposit > 0) {
                uint256 penalty = 0;
                if (bid.penaltyAmount == 0) {
                    bid.penaltyAmount = bid.deposit / 2; // Penalize 50% of the deposit
                    penalty = bid.penaltyAmount;
                } else {
                    penalty = bid.penaltyAmount; // If already penalized, use the existing penalty amount
                }
                bid.deposit -= penalty; // Prevent double claiming of penalty
                penaltyAmount += penalty;
                notRevealdCount++;
            }
        }
        claimOnBehalfOffset += totalAmount;
        if (claimOnBehalfOffset >= bidders.length) {
            claimedPenaltyDone = true; // All bidders have been processed
        }

        if (penaltyAmount > 0) {
            (bool sent, ) = payable(seller).call{value: penaltyAmount}("");
            require(sent, "Failed to pay penalty");

            emit BidPenalized(seller, penaltyAmount, notRevealdCount);
        }
    }

    function changeSeller(address newSeller) external onlySeller {
        require(newSeller != address(0), "Invalid new seller address");
        address oldSeller = seller;
        seller = newSeller;
        emit SellerChanged(oldSeller, newSeller);
    }
}
