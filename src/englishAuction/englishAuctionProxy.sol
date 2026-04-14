// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EnglishAuctionStorage} from "./englishAuctionStorage.sol";
import {EnglishAuctionLogic} from "./englishAuctionLogic.sol";

contract EnglishAuctionProxy is EnglishAuctionStorage {
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("english.auction.proxy.admin")) - 1);

    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);

    address public immutable LOGIC;

    constructor(address _logic,
        uint256 _tokenAmount,
        uint256 _startPrice) {
        require(_logic != address(0), "Logic address must not be zero");
        _setAdmin(msg.sender);

        LOGIC = _logic;

        (bool success, bytes memory data) = _logic.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.initialize.selector, _tokenAmount, _startPrice)
        );
        require(success, _getRevertMsg(data));
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
    function _setAdmin(address newAdmin) private {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
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

    function startAuction(address _token, uint256 _duration) external {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.startAuction.selector, _token, _duration)
        );
        require(success, _getRevertMsg(data));
    }

    function bid() external payable {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.bid.selector)
        );
        require(success, _getRevertMsg(data));
    }

    function withdraw() external {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.withdraw.selector)
        );
        require(success, _getRevertMsg(data));
    }

    function doneAuction() external {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.doneAuction.selector)
        );
        require(success, _getRevertMsg(data));
    }

    function getCurrentPrice() external view returns (uint256) {
        // Keep a read-only external API while executing logic in proxy storage context.
        (bool success, bytes memory data) = address(this).staticcall(
            abi.encodeWithSelector(this.getCurrentPriceDelegate.selector)
        );
        require(success, _getRevertMsg(data));
        return abi.decode(data, (uint256));
    }

    function getCurrentPriceDelegate() external returns (uint256) {
        require(msg.sender == address(this), "Only self call");
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.getCurrentPrice.selector)
        );
        require(success, _getRevertMsg(data));
        return abi.decode(data, (uint256));
    }

    function reclaim() external {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.reclaim.selector)
        );
        require(success, _getRevertMsg(data));
    }

    function cancelAuction() external {
        (bool success, bytes memory data) = LOGIC.delegatecall(
            abi.encodeWithSelector(EnglishAuctionLogic.cancelAuction.selector)
        );
        require(success, _getRevertMsg(data));
    }
}