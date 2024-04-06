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

    uint256 private constant _DEAD_SHARES_VALUE = 0.01 ether;
    address private immutable _implementation = address(new MinerETH());

    /// @notice Deployed minimal proxies for each reward token.
    mapping(address rewardToken => address clone) public deployments;

    event Deploy(address rewardToken);

    error InvalidRewardToken();
    error InsufficientMsgValue();

    /**
     * @notice Deploys a new MinerETH instance for the specified reward token.
     * @param  rewardToken  address  Reward token.
     * @return clone        address  MinerETH minimal proxy contract.
     */
    function deploy(
        address rewardToken
    ) external payable returns (address clone) {
        if (rewardToken == address(0)) revert InvalidRewardToken();
        if (msg.value != _DEAD_SHARES_VALUE) revert InsufficientMsgValue();

        // If an ETH mining vault exists for the reward token, return the existing deployment address.
        if (deployments[rewardToken] != address(0))
            return deployments[rewardToken];

        MinerETH miner = MinerETH(payable(clone = _implementation.clone()));
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

        // Deposit `msg.value` into the mining vault, which are essentially burned since the
        // miner tokens cannot be retrieved from this contract.
        miner.deposit{value: msg.value}("");

        emit Deploy(rewardToken);
    }
}
