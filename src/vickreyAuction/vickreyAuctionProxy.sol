// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {VickreyAuctionStorage} from "./vickreyAuctionStorage.sol";
import {VickreyAuctionLogic} from "./vickreyAuctionLogic.sol";

contract VickreyAuctionProxy is VickreyAuctionStorage {
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("vickrey.auction.proxy.admin")) - 1);   
    
    address public immutable LOGIC;

    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);

    constructor(
        address _vickreyAuctionLogic,
        uint256 _startPrice,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _endDuration) {
        require(_vickreyAuctionLogic != address(0), "Logic contract address cannot be zero");
        _setAdmin(msg.sender);
        LOGIC = _vickreyAuctionLogic;

        (bool success, bytes memory returnData) = _vickreyAuctionLogic.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.initialize.selector, _startPrice, _commitDuration, _revealDuration, _endDuration)
        );
        require(success, _getRevertMsg(returnData));
    }

    function _setAdmin(address newAdmin) private {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }
    function admin() public view returns (address currentAdmin) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            currentAdmin := sload(slot)
        }
    }
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin(), "Only admin can call this function");
        require(newAdmin != address(0), "Admin address cannot be zero");
        address previousAdmin = admin();
        _setAdmin(newAdmin);
        emit AdminUpdated(previousAdmin, newAdmin);
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

    // loser can withdraw their deposit with penalty if they did not reveal their bid before the end of the auction, winner can claim the token and refund excess deposit if any
    function withdrawButNotReveal() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.withdrawButNotReveal.selector)
        );
        require(success, _getRevertMsg(returnData));
    }

    function claim() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.claim.selector)
        );
        require(success, _getRevertMsg(returnData));
    }
    
    // punish the bidder who did not reveal their bid before the end of the auction,
    // let the seller claim the half of the deposit as penalty, and the rest of the deposit will be refunded to the bidder
    function claimOnBehalf() external {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(VickreyAuctionLogic.claimOnBehalf.selector)
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
