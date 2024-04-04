// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrrUSDHelper {
    function redeem(uint256 shares, address to, uint256 minAssets) external;
}
