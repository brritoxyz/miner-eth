// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MinerETHv2Factory} from "src/MinerETHv2Factory.sol";

contract MinerETHv2FactoryScript is Script {
    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        new MinerETHv2Factory();
    }
}
