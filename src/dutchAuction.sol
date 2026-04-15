// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DutchAuction is ReentrancyGuard {
    using SafeERC20 for IERC20;
    enum AuctionStatus {
        Initialized,
        Active,
        Sold,
        Cancelled,
        Expired
    }

    event AuctionCreated(
        address indexed seller,
        uint256 tokenAmount,
        uint256 startPrice,
        uint256 minPrice
    );
    event AuctionStarted(address indexed seller, address indexed token, uint256 start_time, uint256 expire_time);
    event AuctionCancelled(address indexed seller);
    event AuctionSold(address indexed buyer, address indexed seller,uint256 price);
    event AuctionWithdraw(address indexed seller);

    address public immutable SELLER;
    IERC20 public token;
    uint256 public tokenAmount;
    uint256 public immutable INITIAL_TOKEN_AMOUNT;
    uint256 public immutable START_PRICE;
    uint256 public immutable MIN_PRICE;
    uint256 public immutable DURATION;
    uint256 public start_time;
    uint256 public expire_time;
    AuctionStatus public status;

    constructor(
        uint256 _tokenAmount,
        uint256 _startPrice,
        uint256 _minPrice,
        uint256 _duration
    ) {
        require(_tokenAmount > 0, "Token amount must be greater than 0");
        require(_startPrice > 0, "Start price must be greater than 0");
        require(_minPrice > 0, "Min price must be greater than 0");
        require(_startPrice > _minPrice, "Start price must be greater than min price");
        require(_duration > 0, "Duration must be greater than 0");

        SELLER = msg.sender;
        tokenAmount = _tokenAmount;
        INITIAL_TOKEN_AMOUNT = _tokenAmount;
        START_PRICE = _startPrice;
        MIN_PRICE = _minPrice;
        DURATION = _duration;
        status = AuctionStatus.Initialized;

        emit AuctionCreated(
            msg.sender,
            _tokenAmount,
            _startPrice,
            _minPrice
        );
    }

    modifier onlySeller() {
        require(msg.sender == SELLER, "Only seller can call this function");
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
        expire_time = block.timestamp + DURATION;

        token = IERC20(_token);
        token.safeTransferFrom(msg.sender, address(this), tokenAmount);

        emit AuctionStarted(SELLER, address(token), start_time, expire_time);
    }

    function _getCurrentPrice() private view returns (uint256) {
        if (block.timestamp >= expire_time) {
            return MIN_PRICE;
        }
        uint256 elapsedTime = block.timestamp - start_time;
        uint256 totalDuration = expire_time - start_time;
        uint256 priceDecrease = (START_PRICE - MIN_PRICE) * elapsedTime / totalDuration;

        return START_PRICE - priceDecrease;
    }

    function getCurrentPriceByAmount(uint256 _amount) public view returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        uint256 _currentPrice = _getCurrentPrice() * _amount / INITIAL_TOKEN_AMOUNT;
        require(_currentPrice > 0, "Invalid price");
        return _currentPrice;
    }

    function buy() external payable nonReentrant auctionActive auctionNotExpired {
        require(tokenAmount > 0, "Token amount must be greater than 0");

        uint256 _currentPrice = getCurrentPriceByAmount(tokenAmount);
        require(msg.value >= _currentPrice, "Insufficient payment");
        
        status = AuctionStatus.Sold;//update status before transfer to prevent reentrancy attack

        uint256 _amount = tokenAmount;
        tokenAmount = 0; //update token amount before transfer to prevent reentrancy attack
        // Transfer tokens to buyer
        token.safeTransfer(msg.sender, _amount);

        // Refund excess payment
        if (msg.value > _currentPrice) {
            // use call instead of transfer to prevent issues with gas limits and reentrancy
            (bool success, ) = payable(msg.sender).call{value: msg.value - _currentPrice}("");
            require(success, "Failed to refund excess payment");
        }

        // Transfer payment to seller
        (bool sent, ) = payable(SELLER).call{value: _currentPrice}("");
        require(sent, "Failed to transfer payment to seller");

        emit AuctionSold(msg.sender, SELLER, _currentPrice);
    }

    function buySomeToken(uint256 _amount) external payable nonReentrant auctionActive auctionNotExpired {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(_amount > 0 && _amount <= tokenAmount, "Invalid amount");
        uint256 _currentPrice = getCurrentPriceByAmount(_amount);
        require(msg.value >= _currentPrice, "Insufficient payment");

        tokenAmount -= _amount;
        if (tokenAmount == 0) {
            status = AuctionStatus.Sold;
        }

        // send _amount tokens to buyer
        token.safeTransfer(msg.sender, _amount);

        // refund excess payment first
        if (msg.value > _currentPrice) {
            (bool success, ) = payable(msg.sender).call{value: msg.value - _currentPrice}("");
            require(success, "Failed to refund excess payment");
        }

        // send payment to seller
        (bool sent, ) = payable(SELLER).call{value: _currentPrice}("");
        require(sent, "Failed to transfer payment to seller");

        emit AuctionSold(msg.sender, SELLER, _currentPrice);
    }

    function withdraw() external onlySeller auctionActive {
        require(block.timestamp >= expire_time, "Auction has not expired");

        status = AuctionStatus.Expired;

        uint256 remainingAmount = tokenAmount;
        tokenAmount = 0;
        token.safeTransfer(SELLER, remainingAmount);

        emit AuctionWithdraw(SELLER);
    }

    function cancel() external onlySeller auctionActive auctionNotExpired {
        status = AuctionStatus.Cancelled;
        // Return tokens to seller
        token.safeTransfer(SELLER, tokenAmount);

        emit AuctionCancelled(SELLER);
    }
}