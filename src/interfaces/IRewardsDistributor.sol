// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

interface IRewardsDistributor {
    function accrue(ERC20, address) external returns (uint256);

    function accrue(
        ERC20,
        address,
        address
    ) external returns (uint256, uint256);

    function claimRewards(address) external;

    function rewardsAccrued(address) external view returns (uint256);
}
