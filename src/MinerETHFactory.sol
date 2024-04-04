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

    struct Deployment {
        address miner;
        address flywheel;
        address dynamicRewards;
        address rewardsStore;
    }

    string private constant _TOKEN_NAME_PREFIX = "Brrito Miner-";
    string private constant _TOKEN_SYMBOL_PREFIX = "brrMINER-";
    address private immutable implementation =
        address(new InitializableMinerETH());

    mapping(address rewardToken => Deployment) public deployments;

    function deploy(
        string calldata tokenPair,
        address rewardToken
    ) external returns (Deployment memory) {
        Deployment storage deployment = deployments[rewardToken];

        if (deployment.miner != address(0)) return deployment;

        InitializableMinerETH miner = InitializableMinerETH(
            payable(implementation.clone())
        );
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
        deployment.miner = address(flywheel);
        deployment.miner = address(dynamicRewards);
        deployment.rewardsStore = rewardsStore;

        flywheel.setFlywheelRewards(dynamicRewards);
        miner.initialize(
            string.concat(_TOKEN_NAME_PREFIX, tokenPair),
            string.concat(_TOKEN_SYMBOL_PREFIX, tokenPair),
            rewardToken,
            address(flywheel),
            rewardsStore
        );
        flywheel.addStrategyForRewards(ERC20(address(miner)));

        return deployment;
    }
}
