// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DutchAuctionProxy is ERC1967Proxy {
    constructor(address _dutchAuctionLogic, bytes memory _initializeData)
        ERC1967Proxy(_dutchAuctionLogic, _initializeData)
    {}
}
