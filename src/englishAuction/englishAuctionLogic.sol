// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EnglishAuctionStorage} from "./englishAuctionStorage.sol";

contract EnglishAuctionLogic is ReentrancyGuard, EnglishAuctionStorage {
    using SafeERC20 for IERC20;

    function initialize(
        uint256 _tokenAmount,
        uint256 _startPrice,
        bool _antiSniping
    ) external {
        require(!initialized, "Auction is already initialized");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_startPrice > 0, "Start price must be greater than 0");

        initialized = true;
        highestBidder = address(0);
        highestBid = 0;
        SELLER = msg.sender;
        tokenAmount = _tokenAmount;
        startPrice = _startPrice;
        startTime = 0;
        expireTime = 0;

        status = AuctionStatus.Initialized;
        antiSniping = _antiSniping;

        emit AuctionCreated(
            msg.sender,
            _tokenAmount,
            _startPrice
        );
    }

    modifier onlySeller {
        require(msg.sender == SELLER, "Only seller can call this function");
        _;
    }
    modifier notExpired {
        require(block.timestamp < expireTime, "Auction has expired");
        _;
    }

    function startAuction(address _token, uint256 _duration) external onlySeller nonReentrant {
        require(address(_token) != address(0), "Invalid token address");
        require(status == AuctionStatus.Initialized, "Auction already started");
        require(_duration > 0, "Duration must be greater than 0");

        token = IERC20(_token);
        startTime = block.timestamp;
        expireTime = block.timestamp + _duration;
        status = AuctionStatus.Active;

        token.safeTransferFrom(msg.sender, address(this), tokenAmount);
        emit AuctionStarted(msg.sender, address(token), startTime, expireTime);
    }

    function bid() external payable nonReentrant notExpired {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(msg.value > highestBid, "Bid must be higher than current highest bid");
        require(msg.value >= startPrice, "Bid must be at least the start price");

        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;


        // If anti-sniping is enabled and the bid is placed within the last 5 minutes, extend the auction by 5 minutes
        if (antiSniping) {
            if (expireTime - block.timestamp < 5 minutes) {
                expireTime = block.timestamp + 5 minutes;
            }
        }
        emit AuctionBid(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        require(status > AuctionStatus.Active || block.timestamp >= expireTime, "Auction is not ended yet");

        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingReturns[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to withdraw funds");

        emit AuctionWithdraw(msg.sender, amount);
    }

    function doneAuction() external nonReentrant onlySeller {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp >= expireTime, "Auction has not expired");
        require(highestBidder != address(0), "No highest bid");

        status = AuctionStatus.Sold;
        token.safeTransfer(highestBidder, tokenAmount);

        (bool sent, ) = payable(SELLER).call{value: highestBid}("");
        require(sent, "Failed to send funds to seller");
        emit AuctionSold(highestBidder, SELLER, highestBid);
    }

    function getCurrentPrice() external view returns (uint256) {
        if (status != AuctionStatus.Active) {
            return 0;
        }
        if (block.timestamp >= expireTime) {
            return 0;
        }
        return highestBid > 0 ? highestBid : startPrice;
    }

    function reclaim() external nonReentrant onlySeller {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp > expireTime, "Auction has not expired");
        require(highestBidder == address(0), "Cannot reclaim with active bid");
        status = AuctionStatus.Cancelled;
        token.safeTransfer(SELLER, tokenAmount);
        emit AuctionReclaimed(SELLER);
    }

    function cancelAuction() external onlySeller nonReentrant {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp < expireTime, "Auction has expired");
        require(highestBidder == address(0), "Cannot cancel auction with active bids");

        status = AuctionStatus.Cancelled;

        token.safeTransfer(SELLER, tokenAmount);
        emit AuctionCancelled(msg.sender);
    }
}