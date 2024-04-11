// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMoonwellHelper {
    function calculateDeposit(
        address market,
        uint256 assets
    ) external view returns (uint256 tokens);

    function calculateRedeem(
        address market,
        uint256 tokens
    ) external view returns (uint256 assets);
}
