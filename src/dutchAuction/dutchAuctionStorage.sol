// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DutchAuctionStorage {
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

    address public seller;
    uint256 public tokenAmount;
    uint256 public startPrice;
    uint256 public minPrice;
    uint256 public duration;

    IERC20 public token;
    uint256 public start_time;
    uint256 public expire_time;
    AuctionStatus public status;
}