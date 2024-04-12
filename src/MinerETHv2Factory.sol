// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {IFlywheelRewards} from "flywheel-v2/interfaces/IFlywheelRewards.sol";
import {IFlywheelBooster} from "flywheel-v2/interfaces/IFlywheelBooster.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {DynamicRewards} from "src/DynamicRewards.sol";
import {MinerETHv2} from "src/MinerETHv2.sol";

contract MinerETHv2Factory {
    using LibClone for address;

    address public immutable implementation = address(new MinerETHv2());

    /// @notice Deployed minimal proxies for each reward token.
    mapping(address rewardToken => address clone) public deployments;

    event Deploy(address rewardToken);

    error InvalidRewardToken();
    error InsufficientMsgValue();

    /**
     * @notice Deploys a new MinerETHv2 instance for the specified reward token.
     * @param  rewardToken  address  Reward token.
     * @return clone        address  MinerETHv2 minimal proxy contract.
     */
    function deploy(address rewardToken) external returns (address clone) {
        if (rewardToken == address(0)) revert InvalidRewardToken();

        // If an ETH mining vault exists for the reward token, return the existing deployment address.
        if (deployments[rewardToken] != address(0))
            return deployments[rewardToken];

        MinerETHv2 miner = MinerETHv2(payable(clone = implementation.clone()));
        FlywheelCore flywheel = new FlywheelCore(
            ERC20(rewardToken),
            IFlywheelRewards(address(0)),
            IFlywheelBooster(address(0)),
            address(this),
            Authority(address(0))
        );
        DynamicRewards dynamicRewards = new DynamicRewards(flywheel);
        address rewardsStore = address(dynamicRewards.rewardsStore());

        // Store the deployment to enable ease of retrieval and prevent redundant deployments.
        deployments[rewardToken] = clone;

        // Configure flywheel to handle reward accounting and distribution for the mining vault.
        // Transfers flywheel ownership to the zero address to prevent further changes.
        flywheel.setFlywheelRewards(dynamicRewards);
        miner.initialize(rewardToken, address(flywheel), rewardsStore);
        flywheel.addStrategyForRewards(ERC20(address(miner)));
        flywheel.transferOwnership(address(0));

        emit Deploy(rewardToken);
    }
}
