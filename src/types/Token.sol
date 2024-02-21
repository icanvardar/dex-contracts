// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPair } from "../interfaces/IPair.sol";

type Token is address;

using TokenLibrary for Token global;

using Address for address;

library TokenLibrary {
    function computePairAddress(Token token0, Token token1, address factory) internal pure returns (address) {
        return Create2.computeAddress(
            keccak256(abi.encodePacked(Token.unwrap(token0), Token.unwrap(token1))),
            0x055070e0e796ae2b6c2f27913d8d6fcaa8bf006a4fcbb73f8b804ed17bd0fb4a,
            factory
        );
    }

    // prototype of swapExactTokensForTokens function in uniswap v2 router
    function calculateAmounts(
        Token token0,
        address pairAddress,
        uint256 amountIn,
        address input
    )
        internal
        view
        returns (uint256, uint256)
    {
        (uint256 reserve0, uint256 reserve1,) = IPair(pairAddress).getReserves();

        (uint256 reserveIn, uint256 reserveOut) =
            input == Token.unwrap(token0) ? (reserve0, reserve1) : (reserve1, reserve0);

        if (reserveIn == 0 || reserveOut == 0) {
            return (amountIn, 0);
        }

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        return (amountIn, amountOut);
    }

    function safeTransferFrom(Token token, address from, address to, uint256 value) internal returns (bool) {
        try IERC20(Token.unwrap(token)).transferFrom(from, to, value) {
            return true;
        } catch {
            return false;
        }
    }
}
