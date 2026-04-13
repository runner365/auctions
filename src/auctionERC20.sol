// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract AuctionERC20 is ERC20 {
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        address initialAccount
    ) ERC20(name, symbol) {
        require(initialSupply > 0, "initialSupply must be greater than 0");
        require(initialAccount != address(0), "initialAccount must be a valid address");

        _mint(initialAccount, initialSupply);
    }
}
