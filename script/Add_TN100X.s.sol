// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MinerETHv2Factory} from "src/MinerETHv2Factory.sol";
import {MinerETHv2} from "src/MinerETHv2.sol";

contract MinerETHv2Script is Script {
    MinerETHv2Factory public constant FACTORY =
        MinerETHv2Factory(0x434ee23C3ca5a59AD3c30c65ccdd759230184363);
    uint256 public constant SEED_VALUE = 0.02 ether;
    uint256 public constant DEAD_VALUE = 0.01 ether;
    address public constant DEAD = address(0xdead);
    address public constant TN100X = 0x5B5dee44552546ECEA05EDeA01DCD7Be7aa6144A;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Deploy, initialize, and seed each vault with "dead shares" to deter dos'ing.
        MinerETHv2 tn100xMiner = MinerETHv2(payable(FACTORY.deploy(TN100X)));

        tn100xMiner.deposit{value: SEED_VALUE}("");

        // Burn shares to ensure there's always interest accruing to offset Moonwell rounding.
        tn100xMiner.transfer(DEAD, DEAD_VALUE);

        vm.stopBroadcast();
    }
}
