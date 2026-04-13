// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {VickreyAuction} from "../src/vickreyAuction.sol";

contract VickreyAuctionScript is Script {
    VickreyAuction public auction;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 startPrice = vm.envOr("START_PRICE", uint256(1 ether));
        uint256 commitDuration = vm.envOr("COMMIT_DURATION", uint256(5 minutes));
        uint256 revealDuration = vm.envOr("REVEAL_DURATION", uint256(5 minutes));
        uint256 endDuration = vm.envOr("END_DURATION", uint256(5 minutes));

        vm.startBroadcast(deployerPrivateKey);
        auction = new VickreyAuction(
            startPrice,
            commitDuration,
            revealDuration,
            endDuration
        );
        vm.stopBroadcast();
    }
}
