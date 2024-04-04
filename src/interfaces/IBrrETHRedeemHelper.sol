// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrrETHRedeemHelper {
    function redeem(uint256 shares, address to) external;
}
