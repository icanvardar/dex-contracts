// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IPair } from "../../src/interfaces/IPair.sol";
import { ICallee } from "../../src/interfaces/ICallee.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockFlashSwap
 * @dev The MockFlashSwap contract represents a communication with uniswap pair contract
 */
contract MockFlashSwap is ICallee {
    uint256 private expectedLoanAmount;

    /**
     * @dev flashSwap function. This function is called uniswap pair contract. we requested to borrow.
     * @param pairAddress Pair address of uniswap.
     * @param amount0Out Amount of token0 to be sent out in the swap.
     * @param amount1Out Amount of token1 to be sent out in the swap.
     * @param tokenAddress Uniswap pool token address.
     */
    function flashSwap(address pairAddress, uint256 amount0Out, uint256 amount1Out, address tokenAddress) external {
        bytes memory data = abi.encode(tokenAddress, msg.sender);
        IPair(pairAddress).swap(amount0Out, amount1Out, address(this), data);
    }

    /**
     * @dev uniswapV2Call function. This function is called by the uniswap pair contract. we will have to repay the
     * amount that we borrowed plus some fees.
     * @param sender Will hold the address that initiated the flash loan.
     * @param amount0Out Amount of token0 to be sent out in the swap.
     * @param amount1Out Amount of token1 to be sent out in the swap.
     * @param data Additional data for the recipient contract's callback function.
     */
    function uniswapV2Call(address sender, uint256 amount0Out, uint256 amount1Out, bytes calldata data) external {
        (address tokenAddress, address caller) = abi.decode(data, (address, address));

        if (amount0Out > 0) {
            expectedLoanAmount = amount0Out;
        }
        if (amount1Out > 0) {
            expectedLoanAmount = amount1Out;
        }

        // about 0.3% fee, +1 to round up
        uint256 fee = (expectedLoanAmount * 3) / 997 + 1;
        uint256 amountToRepay = expectedLoanAmount + fee;

        IERC20(tokenAddress).transferFrom(caller, sender, fee);

        IERC20(tokenAddress).transfer(msg.sender, amountToRepay);
    }
}
