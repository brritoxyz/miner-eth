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
    address public constant ELON = 0xAa6Cccdce193698D33deb9ffd4be74eAa74c4898;
    address public constant NFD = 0x37289326b7Bca5a776A5071b8d693C0588c5C9A6;
    address public constant DEGEN = 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed;
    address public constant DOG = 0xAfb89a09D82FBDE58f18Ac6437B3fC81724e4dF6;
    address public constant MFER = 0xE3086852A4B125803C815a158249ae468A3254Ca;

    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        // Deploy, initialize, and seed each vault with "dead shares" to deter dos'ing.
        MinerETHv2 elonMiner = MinerETHv2(payable(FACTORY.deploy(ELON)));
        MinerETHv2 nfdMiner = MinerETHv2(payable(FACTORY.deploy(NFD)));
        MinerETHv2 degenMiner = MinerETHv2(payable(FACTORY.deploy(DEGEN)));
        MinerETHv2 dogMiner = MinerETHv2(payable(FACTORY.deploy(DOG)));
        MinerETHv2 mferMiner = MinerETHv2(payable(FACTORY.deploy(MFER)));

        elonMiner.deposit{value: SEED_VALUE}("");
        nfdMiner.deposit{value: SEED_VALUE}("");
        degenMiner.deposit{value: SEED_VALUE}("");
        dogMiner.deposit{value: SEED_VALUE}("");
        mferMiner.deposit{value: SEED_VALUE}("");

        // Burn shares to ensure there's always interest accruing to offset Moonwell rounding.
        elonMiner.transfer(DEAD, DEAD_VALUE);
        nfdMiner.transfer(DEAD, DEAD_VALUE);
        degenMiner.transfer(DEAD, DEAD_VALUE);
        dogMiner.transfer(DEAD, DEAD_VALUE);
        mferMiner.transfer(DEAD, DEAD_VALUE);

        vm.stopBroadcast();
    }
}
