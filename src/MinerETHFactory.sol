// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {FlywheelCore} from "flywheel-v2/FlywheelCore.sol";
import {IFlywheelRewards} from "flywheel-v2/interfaces/IFlywheelRewards.sol";
import {IFlywheelBooster} from "flywheel-v2/interfaces/IFlywheelBooster.sol";
import {LibClone} from "solady/utils/LibClone.sol";
import {Authority} from "solmate/auth/Auth.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {DynamicRewards} from "src/DynamicRewards.sol";
import {MinerETH} from "src/MinerETH.sol";

contract MinerETHFactory {
    using LibClone for address;

    struct Deployment {
        address miner;
        address flywheel;
        address dynamicRewards;
        address rewardsStore;
    }

    address private immutable implementation = address(new MinerETH());

    mapping(address rewardToken => Deployment) public deployments;

    event Deploy(address rewardToken);

    error InvalidRewardToken();

    function deploy(address rewardToken) external returns (Deployment memory) {
        if (rewardToken == address(0)) revert InvalidRewardToken();

        Deployment storage deployment = deployments[rewardToken];

        if (deployment.miner != address(0)) return deployment;

        MinerETH miner = MinerETH(payable(implementation.clone()));
        FlywheelCore flywheel = new FlywheelCore(
            ERC20(rewardToken),
            IFlywheelRewards(address(0)),
            IFlywheelBooster(address(0)),
            address(this),
            Authority(address(0))
        );
        DynamicRewards dynamicRewards = new DynamicRewards(flywheel);
        address rewardsStore = address(dynamicRewards.rewardsStore());

        // Store the deployment to enable ease of retrieval and preventing redundant deployments.
        deployment.miner = address(miner);
        deployment.flywheel = address(flywheel);
        deployment.dynamicRewards = address(dynamicRewards);
        deployment.rewardsStore = rewardsStore;

        flywheel.setFlywheelRewards(dynamicRewards);
        miner.initialize(rewardToken, address(flywheel), rewardsStore);
        flywheel.addStrategyForRewards(ERC20(address(miner)));
        flywheel.transferOwnership(address(0));

        emit Deploy(rewardToken);

        return deployment;
    }
}
