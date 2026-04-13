// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DutchAuction} from "../src/dutchAuction.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DutchAuctionScript is Script {
    DutchAuction public auction;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        uint256 tokenAmount = vm.envOr("TOKEN_AMOUNT", uint256(100 ether));
        uint256 startPrice = vm.envOr("START_PRICE", uint256(1 ether));
        uint256 minPrice = vm.envOr("MIN_PRICE", uint256(0.01 ether));
        uint256 duration = vm.envOr("DURATION", uint256(5 minutes));

        vm.startBroadcast(deployerPrivateKey);

        auction = new DutchAuction(
            tokenAmount,
            startPrice,
            minPrice,
            duration
        );
        vm.stopBroadcast();
    }
}