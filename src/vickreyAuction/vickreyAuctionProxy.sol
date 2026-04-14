// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {VickreyAuctionStorage} from "./vickreyAuctionStorage.sol";
import {VickreyAuctionLogic} from "./vickreyAuctionLogic.sol";

contract VickreyAuctionProxy is ReentrancyGuard, VickreyAuctionStorage {
    using SafeERC20 for IERC20;

    address public immutable LOGIC;

    constructor(
        address _vickreyAuctionLogic,
        uint256 _startPrice,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _endDuration) {
        require(_vickreyAuctionLogic != address(0), "Logic contract address cannot be zero");

        LOGIC = _vickreyAuctionLogic;

        (bool success, bytes memory returnData) = _vickreyAuctionLogic.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.initialize.selector, _startPrice, _commitDuration, _revealDuration, _endDuration)
        );
        require(success, _getRevertMsg(returnData));
    }

    function startAuction(address _token, uint256 _tokenAmount) external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.startAuction.selector, _token, _tokenAmount)
        );
        require(success, _getRevertMsg(returnData));
    }

    function commitBid(bytes32 _bidHash) external payable {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.commitBid.selector, _bidHash)
        );
        require(success, _getRevertMsg(returnData));
    }

    function revealBid(uint256 _bidAmount, string calldata _secret) external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.revealBid.selector, _bidAmount, _secret)
        );
        require(success, _getRevertMsg(returnData));
    }

    function endAuction() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.endAuction.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function withdrawFund() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.withdrawFund.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function withdraw() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.withdraw.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function claim() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.claim.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function _getRevertMsg(bytes memory _returnData) internal pure returns (string memory) {
        if (_returnData.length < 68) return "Transaction reverted silently";
        assembly {
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string));
    }

}
