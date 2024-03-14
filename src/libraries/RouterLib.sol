// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

import { IPair } from "../interfaces/IPair.sol";

/**
 * @title RouterLib
 * @dev A library containing utility functions for interacting with liquidity pools.
 */
library RouterLib {
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Error indicating that two addresses provided are identical
    error IdenticalAddresses();
    /// @notice Error indicating that an address provided is zero
    error ZeroAddress();
    /// @notice Error indicating that there is insufficient liquidity for a transaction
    error InsufficientLiquidity();
    /// @notice Error indicating that the output amount in a transaction is insufficient
    error InsufficientOutputAmount();
    /// @notice Error indicating that the input amount in a transaction is insufficient
    error InsufficientInputAmount();
    /// @notice Error indicating that the amount provided is insufficient for the operation
    error InsufficientAmount();
    /// @notice Error indicating that the path provided for a transaction is invalid
    error InvalidPath();

    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the sorted order of two token addresses.
     * @param tokenA The first token address.
     * @param tokenB The second token address.
     * @return token0 The address of the token with a smaller address.
     * @return token1 The address of the token with a larger address.
     */
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) {
            revert IdenticalAddresses();
        }
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert ZeroAddress();
        }
    }

    /**
     * @dev Calculates the CREATE2 address for a pair without making any external calls.
     * @param factory The address of the factory contract.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return pair The calculated pair address.
     */
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = Create2.computeAddress(
            keccak256(abi.encodePacked(token0, token1)),
            0x055070e0e796ae2b6c2f27913d8d6fcaa8bf006a4fcbb73f8b804ed17bd0fb4a,
            factory
        );
    }

    /**
     * @dev Fetches and sorts the reserves for a pair.
     * @param factory The address of the factory contract.
     * @param tokenA The address of the first token.
     * @param tokenB The address of the second token.
     * @return reserveA The reserve of tokenA in the pair.
     * @return reserveB The reserve of tokenB in the pair.
     */
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    )
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IPair(pairFor(factory, tokenA, tokenB)).getReserves();

        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset.
     * @param amountA The input amount.
     * @param reserveA The reserve of the input token.
     * @param reserveB The reserve of the output token.
     * @return amountB The equivalent amount of the output token.
     */
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        if (amountA == 0) {
            revert InsufficientAmount();
        }
        if (reserveA == 0 || reserveB == 0) {
            revert InsufficientLiquidity();
        }
        amountB = (amountA * reserveB) / reserveA;
    }

    /**
     * @dev Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset.
     * @param amountIn The input amount.
     * @param reserveIn The reserve of the input token.
     * @param reserveOut The reserve of the output token.
     * @return amountOut The maximum output amount of the output token.
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0) {
            revert InsufficientInputAmount();
        }
        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /**
     * @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset.
     * @param amountOut The output amount.
     * @param reserveIn The reserve of the input token.
     * @param reserveOut The reserve of the output token.
     * @return amountIn The required input amount of the input token.
     */
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    )
        internal
        pure
        returns (uint256 amountIn)
    {
        if (amountOut == 0) {
            revert InsufficientOutputAmount();
        }
        if (reserveIn == 0 || reserveOut == 0) {
            revert InsufficientLiquidity();
        }
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /**
     * @dev Performs chained getAmountOut calculations on any number of pairs.
     * @param factory The address of the factory contract.
     * @param amountIn The input amount.
     * @param path An array of token addresses representing the path.
     * @return amounts An array of output amounts for each step in the path.
     */
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    )
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert InvalidPath();
        }
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /**
     * @dev Performs chained getAmountIn calculations on any number of pairs.
     * @param factory The address of the factory contract.
     * @param amountOut The output amount.
     * @param path An array of token addresses representing the path.
     * @return amounts An array of input amounts for each step in the path.
     */
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    )
        internal
        view
        returns (uint256[] memory amounts)
    {
        if (path.length < 2) {
            revert InvalidPath();
        }
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
