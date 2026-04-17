// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EnglishAuctionProxy is ERC1967Proxy {
    constructor(address _englishAuctionLogic, bytes memory _initializeData)
        ERC1967Proxy(_englishAuctionLogic, _initializeData)
    {}
}
