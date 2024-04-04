// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IBrrUSD {
    function deposit(
        uint256 amount,
        address to,
        uint256 minShares
    ) external returns (uint256 shares);

    function convertToShares(
        uint256 assets,
        uint256 totalSupply,
        uint256 totalAssets
    ) external pure returns (uint256);

    function convertToShares(uint256 assets) external view returns (uint256);

    function convertToAssets(uint256 shares) external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function harvest() external;
}
