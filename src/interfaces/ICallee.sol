// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

interface ICallee {
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
