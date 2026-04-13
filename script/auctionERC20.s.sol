// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {AuctionERC20} from "../src/auctionERC20.sol";

contract AuctionERC20Script is Script {
    AuctionERC20 public token;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory name = vm.envOr("TOKEN_NAME", string("Auction Token"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("AUCT"));
        uint256 initialSupply = vm.envOr("INITIAL_SUPPLY", uint256(1_000_000 ether));
        address initialAccount = vm.envOr("INITIAL_ACCOUNT", deployer);

        vm.startBroadcast(deployerPrivateKey);
        token = new AuctionERC20(name, symbol, initialSupply, initialAccount);
        vm.stopBroadcast();
    }
}
