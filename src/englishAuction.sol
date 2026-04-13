// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EnglishAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;
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
        uint256 start_time,
        uint256 expire_time
    );
    event AuctionBid(
        address indexed bidder,
        uint256 bidAmount
    );
    event AuctionWithdraw(address indexed bidder, uint256 amount);
    event AuctionSold(address indexed buyer, address indexed seller, uint256 price);
    event AuctionCancelled(address indexed seller);
    event AuctionReclaimed(address indexed seller);
    
    address public immutable SELLER;
    IERC20 public token;
    uint256 public immutable TOKEN_AMOUNT;
    uint256 public immutable START_PRICE;
    uint256 public start_time;
    uint256 public expire_time;
    AuctionStatus public status;
    address public highestBidder;
    uint256 public highestBid;
    mapping(address => uint256) public pendingReturns;

    constructor(
        uint256 _tokenAmount,
        uint256 _startPrice
    ) {
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_startPrice > 0, "Start price must be greater than 0");

        highestBidder = address(0);
        highestBid = 0;
        SELLER = msg.sender;
        TOKEN_AMOUNT = _tokenAmount;
        START_PRICE = _startPrice;
        
        status = AuctionStatus.Initialized;

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
        require(block.timestamp < expire_time, "Auction has expired");
        _;
    }

    function startAuction(address _token, uint256 _duration) external onlySeller nonReentrant {
        require(address(_token) != address(0), "Invalid token address");
        require(status == AuctionStatus.Initialized, "Auction already started");
        require(_duration > 0, "Duration must be greater than 0");

        token = IERC20(_token);
        start_time = block.timestamp;
        expire_time = block.timestamp + _duration;
        status = AuctionStatus.Active;

        token.safeTransferFrom(msg.sender, address(this), TOKEN_AMOUNT);    
        emit AuctionStarted(msg.sender, address(token), start_time, expire_time);
    }

    function bid() external payable nonReentrant notExpired {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(msg.value > highestBid, "Bid must be higher than current highest bid");
        require(msg.value >= START_PRICE, "Bid must be at least the start price");

        if (highestBidder != address(0)) {
            pendingReturns[highestBidder] += highestBid;
        }

        highestBidder = msg.sender;
        highestBid = msg.value;

        emit AuctionBid(msg.sender, msg.value);
    }

    function withdraw() external nonReentrant {
        require(status > AuctionStatus.Active || block.timestamp >= expire_time, "Auction is not ended yet");

        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "No funds to withdraw");

        pendingReturns[msg.sender] = 0;

        (bool sent, ) = payable(msg.sender).call{value: amount}("");
        require(sent, "Failed to withdraw funds");

        emit AuctionWithdraw(msg.sender, amount);
    }

    function doneAuction() external nonReentrant onlySeller {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp >= expire_time, "Auction has not expired");
        require(highestBidder != address(0), "No highest bid");

        status = AuctionStatus.Sold;
        token.safeTransfer(highestBidder, TOKEN_AMOUNT);

        (bool sent, ) = payable(SELLER).call{value: highestBid}("");
        require(sent, "Failed to send funds to seller");
        emit AuctionSold(highestBidder, SELLER, highestBid);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (status != AuctionStatus.Active) {
            return 0;
        }
        if (block.timestamp >= expire_time) {
            return 0;
        }
        return highestBid > 0 ? highestBid : START_PRICE;
    }

    function reclaim() external nonReentrant onlySeller {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp > expire_time, "Auction has not expired");
        require(highestBidder == address(0), "Cannot reclaim with active bid");
        status = AuctionStatus.Cancelled;
        token.safeTransfer(SELLER, TOKEN_AMOUNT);
        emit AuctionReclaimed(SELLER);
    }

    function cancelAuction() external onlySeller nonReentrant {
        require(status == AuctionStatus.Active, "Auction is not active");
        require(block.timestamp < expire_time, "Auction has expired");
        require(highestBidder == address(0), "Cannot cancel auction with active bids");

        status = AuctionStatus.Cancelled;

        token.safeTransfer(SELLER, TOKEN_AMOUNT);
        emit AuctionCancelled(msg.sender);
    }
}