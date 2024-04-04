// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {FlywheelDynamicRewards} from "src/FlywheelDynamicRewards.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeCastLib} from "solady/utils/SafeCastLib.sol";
import {RewardsStore} from "src/RewardsStore.sol";

contract DynamicRewards is FlywheelDynamicRewards {
    using SafeCastLib for uint256;

    RewardsStore public immutable rewardsStore;

    error InvalidAddress();

    constructor(FlywheelCore _flywheel) FlywheelDynamicRewards(_flywheel) {
        rewardsStore = new RewardsStore(address(rewardToken), address(this));
    }

    /**
     * @notice Retrieve the next cycle's rewards from the store and return the
     *         amount of tokens received.
     * @param  strategy  ERC20    The strategy to accrue rewards for.
     * @return amount    uint256  The amount of tokens accrued and transferred.
     */
    function getAccruedRewards(
        ERC20 strategy,
        uint32
    ) external override onlyFlywheel returns (uint256 amount) {
        return getNextCycleRewards(strategy);
    }

    /**
     * @notice Retrieves next cycle's rewards from the store contract to ensure proper accounting.
     * @dev    For the sake of simplicity, we're not making use of the `strategy` param (assumption
     *         is that the only strategy is the miner token - if this changes later, can update
     *         FlywheelRewards). FlywheelCore also adds a layer of protection by checking whether
     *         the strategy exists before calling `FlywheelDynamicRewards.getAccruedRewards`.
     */
    function getNextCycleRewards(ERC20) internal override returns (uint192) {
        return rewardsStore.transferNextCycleRewards().toUint192();
    }
}
