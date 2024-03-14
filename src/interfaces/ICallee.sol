// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title ICallee
 * @dev Interface for contracts that can be called by UniswapV2 contracts using the `uniswapV2Call` function.
 */
interface ICallee {
    /**
     * @dev Function called by UniswapV2 contracts when a swap occurs.
     * @param sender The address initiating the swap.
     * @param amount0 The amount of the first token in the pair.
     * @param amount1 The amount of the second token in the pair.
     * @param data Additional data to be passed to the callee.
     */
    function uniswapV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
