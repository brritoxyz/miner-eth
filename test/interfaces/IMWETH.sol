// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IMWETH {
    function accrueInterest() external returns (uint256);
}
