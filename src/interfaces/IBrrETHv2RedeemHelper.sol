// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrrETHv2RedeemHelper {
    function redeem(
        uint256 shares,
        address to,
        uint256 minAssets
    ) external returns (uint256 assets);
}
