// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DutchAuctionStorage} from "./dutchAuctionStorage.sol";
import {DutchAuctionLogic} from "./dutchAuctionLogic.sol";

contract DutchAuctionProxy is DutchAuctionStorage {
    bytes32 private constant ADMIN_SLOT = bytes32(uint256(keccak256("dutch.auction.proxy.admin")) - 1);

    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);

    address public immutable LOGIC;

    constructor(address _logic, 
            uint256 _tokenAmount, 
            uint256 _startPrice, 
            uint256 _minPrice, 
            uint256 _duration) {
        require(_logic != address(0), "Logic contract address cannot be zero");
        _setAdmin(msg.sender);
        LOGIC = _logic;

        (bool success, bytes memory returnData) = _logic.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.initialize.selector, _tokenAmount, _startPrice, _minPrice, _duration)
        );
        require(success, _getRevertMsg(returnData));
    }

    modifier onlyAdmin() {
        require(msg.sender == admin(), "Only admin can call this function");
        _;
    }

    function admin() public view returns (address currentAdmin) {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            currentAdmin := sload(slot)
        }
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Admin address cannot be zero");

        address previousAdmin = admin();
        _setAdmin(newAdmin);

        emit AdminUpdated(previousAdmin, newAdmin);
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

    function buySomeToken(uint256 _amount) external payable {
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.buySomeToken.selector, _amount)
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

    function getCurrentPriceByAmount(uint256 _amount) external view returns (uint256) {
        (bool success, bytes memory returnData) = address(this).staticcall(
            abi.encodeWithSelector(this.getCurrentPriceByAmountDelegate.selector, _amount)
        );
        require(success, _getRevertMsg(returnData));
        return abi.decode(returnData, (uint256));
    }

    function getCurrentPriceByAmountDelegate(uint256 _amount) external returns (uint256) {
        require(msg.sender == address(this), "Only self call");
        (bool success, bytes memory returnData) = LOGIC.delegatecall(
            abi.encodeWithSelector(DutchAuctionLogic.getCurrentPriceByAmount.selector, _amount)
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

    function _setAdmin(address newAdmin) internal {
        bytes32 slot = ADMIN_SLOT;
        assembly {
            sstore(slot, newAdmin)
        }
    }
}
