// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

contract RewardsStore {
    using SafeTransferLib for address;

    address public immutable rewardToken;
    address public immutable flywheelRewards;

    error Unauthorized();

    constructor(address _rewardToken, address _flywheelRewards) {
        rewardToken = _rewardToken;
        flywheelRewards = _flywheelRewards;
    }

    /**
     * @notice Transfers next cycle's rewards to the FlywheelRewards contract.
     * @return amount  uint256  Reward amount.
     */
    function transferNextCycleRewards() external returns (uint256 amount) {
        if (msg.sender != flywheelRewards) revert Unauthorized();

        amount = rewardToken.balanceOf(address(this));

        rewardToken.safeTransfer(msg.sender, amount);
    }
}
