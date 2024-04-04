// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {IFlywheelRewards} from "flywheel-v2/interfaces/IFlywheelRewards.sol";
import {IFlywheelBooster} from "flywheel-v2/interfaces/IFlywheelBooster.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {DynamicRewards} from "src/DynamicRewards.sol";
import {InitializableMinerETH} from "src/InitializableMinerETH.sol";

contract MinerETHFactory {
    using LibClone for address;

    string private constant _TOKEN_NAME_PREFIX = "Brrito Miner-";
    string private constant _TOKEN_SYMBOL_PREFIX = "brrMINER-";
    address private immutable implementation =
        address(new InitializableMinerETH());

    constructor() {
        // Prevent implementation from being initialized by others.
        InitializableMinerETH(payable(implementation)).initialize(
            _TOKEN_NAME_PREFIX,
            _TOKEN_SYMBOL_PREFIX,
            address(0xdead),
            address(0xdead),
            address(0xdead)
        );
    }

    function deploy(
        string calldata tokenPair,
        address rewardToken
    ) external returns (address clone) {
        clone = implementation.clone();
        FlywheelCore flywheel = new FlywheelCore(
            ERC20(rewardToken),
            IFlywheelRewards(address(0)),
            IFlywheelBooster(address(0)),
            address(this),
            Authority(address(0))
        );
        DynamicRewards dynamicRewards = new DynamicRewards(flywheel);

        flywheel.setFlywheelRewards(dynamicRewards);
        InitializableMinerETH(payable(clone)).initialize(
            string.concat(_TOKEN_NAME_PREFIX, tokenPair),
            string.concat(_TOKEN_SYMBOL_PREFIX, tokenPair),
            rewardToken,
            address(flywheel),
            address(dynamicRewards.rewardsStore())
        );
        flywheel.addStrategyForRewards(ERC20(clone));
    }
}
