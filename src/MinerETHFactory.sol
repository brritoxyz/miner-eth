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

    function deploy(
        string calldata tokenPair,
        address rewardToken
    )
        external
        returns (
            address miner,
            address flywheel,
            address dynamicRewards,
            address rewardsStore
        )
    {
        miner = implementation.clone();
        flywheel = address(
            new FlywheelCore(
                ERC20(rewardToken),
                IFlywheelRewards(address(0)),
                IFlywheelBooster(address(0)),
                address(this),
                Authority(address(0))
            )
        );
        dynamicRewards = address(new DynamicRewards(FlywheelCore(flywheel)));
        rewardsStore = address(DynamicRewards(dynamicRewards).rewardsStore());

        FlywheelCore(flywheel).setFlywheelRewards(
            DynamicRewards(dynamicRewards)
        );
        InitializableMinerETH(payable(miner)).initialize(
            string.concat(_TOKEN_NAME_PREFIX, tokenPair),
            string.concat(_TOKEN_SYMBOL_PREFIX, tokenPair),
            rewardToken,
            flywheel,
            rewardsStore
        );
        FlywheelCore(flywheel).addStrategyForRewards(ERC20(miner));
    }
}
