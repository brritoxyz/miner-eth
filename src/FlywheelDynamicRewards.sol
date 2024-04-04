// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {BaseFlywheelRewards} from "flywheel-v2/rewards/BaseFlywheelRewards.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 @title Flywheel Dynamic Reward Stream
 @notice Determines rewards based on a dynamic reward stream.
         Rewards are transferred linearly over a "rewards cycle" to prevent gaming the reward distribution.
         The reward source can be arbitrary logic, but most common is to "pass through" rewards from some other source.
         The getNextCycleRewards() hook should also transfer the next cycle's rewards to this contract to ensure proper accounting.
*/
abstract contract FlywheelDynamicRewards is BaseFlywheelRewards {
    constructor(FlywheelCore _flywheel) BaseFlywheelRewards(_flywheel) {}

    function getAccruedRewards(
        ERC20 strategy,
        uint32 lastUpdatedTimestamp
    ) external virtual returns (uint256 amount);

    function getNextCycleRewards(
        ERC20 strategy
    ) internal virtual returns (uint192);
}
