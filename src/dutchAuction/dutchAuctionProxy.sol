// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {DutchAuctionStorage} from "./dutchAuctionStorage.sol";
import {DutchAuctionLogic} from "./dutchAuctionLogic.sol";

contract DutchAuctionProxy is DutchAuctionStorage {
    address public immutable LOGIC;

    constructor(address _logic, 
            uint256 _tokenAmount, 
            uint256 _startPrice, 
            uint256 _minPrice, 
            uint256 _duration) {
        require(_logic != address(0), "Logic contract address cannot be zero");
        LOGIC = _logic;

        (bool success, bytes memory returnData) = _logic.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.initialize.selector, _tokenAmount, _startPrice, _minPrice, _duration)
        );
        require(success, _getRevertMsg(returnData));
    }

    function start(address _token) external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.start.selector, _token)
        );
        require(success, _getRevertMsg(returnData));
    }

    function buy() external payable {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.buy.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function withdraw() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.withdraw.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function cancel() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.cancel.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function getCurrentPrice() external view returns (uint256) {
        (bool success, bytes memory returnData) = address(this).staticcall(
            abi.encodeWithSelector(this.getCurrentPriceDelegate.selector)
        );
        require(success, _getRevertMsg(returnData));
        return abi.decode(returnData, (uint256));
    }

    function getCurrentPriceDelegate() external returns (uint256) {
        require(msg.sender == address(this), "Only self call");
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.getCurrentPrice.selector)
        );
        require(success, _getRevertMsg(returnData));
        return abi.decode(returnData, (uint256));
    }

    function _getRevertMsg(bytes memory returnData) private pure returns (string memory) {
        if (returnData.length < 68) {
            return "delegatecall failed";
        }
        assembly {
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string));
    }
}
