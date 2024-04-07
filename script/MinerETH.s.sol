// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import {MinerETHFactory} from "src/MinerETHFactory.sol";
import {MinerETH} from "src/MinerETH.sol";

contract MinerETHScript is Script {
    MinerETHFactory public constant FACTORY = MinerETHFactory(address(0));
    uint256 public constant SEED_VALUE = 0.01 ether;
    address public constant ELON = 0xAa6Cccdce193698D33deb9ffd4be74eAa74c4898;
    address public constant NFD = 0x37289326b7Bca5a776A5071b8d693C0588c5C9A6;
    address public constant DEGEN = 0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed;

    function run() public {
        vm.broadcast(vm.envUint("PRIVATE_KEY"));

        // Deploy, initialize, and seed each vault with "dead shares" to deter dos'ing.
        MinerETH elonMiner = MinerETH(payable(FACTORY.deploy(ELON)));
        MinerETH nfdMiner = MinerETH(payable(FACTORY.deploy(NFD)));
        MinerETH degenMiner = MinerETH(payable(FACTORY.deploy(DEGEN)));

        elonMiner.deposit{value: SEED_VALUE}("");
        nfdMiner.deposit{value: SEED_VALUE}("");
        degenMiner.deposit{value: SEED_VALUE}("");
    }
}
