// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MinerETHFactory} from "src/MinerETHFactory.sol";

contract MinerETHFactoryScript is Script {
    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        new MinerETHFactory();
    }
}
