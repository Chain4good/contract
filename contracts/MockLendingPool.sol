// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockLendingPool {
    function deposit(address asset, uint256 amount, address onBehalfOf) external payable {}
    function withdraw(address /*asset*/, uint256 amount, address /*to*/) external pure returns (uint256) {
        return amount;
    }
    function getReserveData(address /*asset*/) external pure returns (uint256) {
        return 5; // 5% APY
    }
}