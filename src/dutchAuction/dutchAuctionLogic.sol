// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {DutchAuctionStorage} from "./dutchAuctionStorage.sol";

contract DutchAuctionLogic is ReentrancyGuard, DutchAuctionStorage {
    using SafeERC20 for IERC20;

    function initialize(
        uint256 _tokenAmount,
        uint256 _startPrice,
        uint256 _minPrice,
        uint256 _duration
    ) external {
        require(!initialized, "Auction is already initialized");
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_startPrice > 0, "Start price must be greater than 0");
        require(_minPrice > 0, "Min price must be greater than 0");
        require(_startPrice > _minPrice, "Start price must be greater than min price");
        require(_duration > 0, "Duration must be greater than 0");
        initialized = true;
        seller = msg.sender;
        initialTokenAmount = _tokenAmount;
        tokenAmount = _tokenAmount;
        startPrice = _startPrice;
        minPrice = _minPrice;
        duration = _duration;

        status = AuctionStatus.Initialized;
    
        emit AuctionCreated(
            msg.sender,
            _tokenAmount,
            _startPrice,
            _minPrice
        );
    }

    modifier onlySeller() {
        require(msg.sender == seller, "Only seller can call this function");
        _;
    }
    modifier auctionActive() {
        require(status == AuctionStatus.Active, "Auction is not active");
        _;
    }
    modifier auctionNotExpired() {
        require(block.timestamp < expire_time, "Auction has expired");
        _;
    }
    
    function start(address _token) external onlySeller nonReentrant {
        require(status == AuctionStatus.Initialized, "Auction is already active");
        status = AuctionStatus.Active;
        start_time = block.timestamp;
        expire_time = block.timestamp + duration;

        token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        emit AuctionStarted(seller, address(token), start_time, expire_time);
    }

    function _getCurrentPrice() private view returns (uint256) {
        if (block.timestamp >= expire_time) {
            return minPrice;
        }
        uint256 elapsedTime = block.timestamp - start_time;
        uint256 totalDuration = expire_time - start_time;
        uint256 priceDecrease = (startPrice - minPrice) * elapsedTime / totalDuration;

        return startPrice - priceDecrease;
    }
    
    function getCurrentPriceByAmount(uint256 _amount) public view returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 _currentPrice = _getCurrentPrice() * _amount / initialTokenAmount;
        require(_currentPrice > 0, "Invalid price");
        return _currentPrice;
    }

    function buy() external payable nonReentrant auctionActive auctionNotExpired {
        uint256 currentPrice = getCurrentPriceByAmount(tokenAmount);
        require(msg.value >= currentPrice, "Insufficient payment");
        
        status = AuctionStatus.Sold;//update status before transfer to prevent reentrancy attack

        // Transfer tokens to buyer
        token.safeTransfer(msg.sender, tokenAmount);

        // Refund excess payment
        if (msg.value > currentPrice) {
            // use call instead of transfer to prevent issues with gas limits and reentrancy
            (bool success, ) = payable(msg.sender).call{value: msg.value - currentPrice}("");
            require(success, "Failed to refund excess payment");
        }

        // Transfer payment to seller
        (bool sent, ) = payable(seller).call{value: currentPrice}("");
        require(sent, "Failed to transfer payment to seller");

        emit AuctionSold(msg.sender, seller, currentPrice);
    }

    function buySomeToken(uint256 _amount) external payable nonReentrant auctionActive auctionNotExpired {
        require(_amount > 0, "Amount must be greater than 0");
        require(_amount <= tokenAmount, "Not enough tokens left");

        uint256 currentPrice = getCurrentPriceByAmount(_amount);
        require(msg.value >= currentPrice, "Insufficient payment");
        
        tokenAmount -= _amount; //update token amount before transfer to prevent reentrancy attack
        if (tokenAmount == 0) {
            status = AuctionStatus.Sold;//update status before transfer to prevent reentrancy attack
        }
        // Transfer tokens to buyer
        token.safeTransfer(msg.sender, _amount);

        // Refund excess payment
        if (msg.value > currentPrice) {
            // use call instead of transfer to prevent issues with gas limits and reentrancy
            (bool success, ) = payable(msg.sender).call{value: msg.value - currentPrice}("");
            require(success, "Failed to refund excess payment");
        }

        // Transfer payment to seller
        (bool sent, ) = payable(seller).call{value: currentPrice}("");
        require(sent, "Failed to transfer payment to seller");

        emit AuctionSold(msg.sender, seller, currentPrice);
    }

    function withdraw() external onlySeller auctionActive {
        require(block.timestamp >= expire_time, "Auction has not expired");
        status = AuctionStatus.Expired;
        // Return tokens to seller
        token.safeTransfer(seller, tokenAmount);
        emit AuctionWithdraw(seller);
    }

    function cancel() external onlySeller auctionActive auctionNotExpired {
        status = AuctionStatus.Cancelled;
        // Return tokens to seller
        token.safeTransfer(seller, tokenAmount);

        emit AuctionCancelled(seller);
    }
}