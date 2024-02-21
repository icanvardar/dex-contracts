// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { SafeCastLib } from "vectorized/solady/utils/SafeCastLib.sol";

/**
 * @title UQ112x112
 * @dev A library for handling binary fixed-point numbers.
 * @notice The resolution is 1 / 2^112, and the range is [0, 2^112 - 1].
 */
library UQ112x112 {
    using SafeCastLib for uint112;

    uint224 constant Q112 = 2 ** 112;

    /**
     * @dev Encodes a uint112 as a UQ112x112.
     * @param y The input uint112 value.
     * @return z The encoded UQ112x112 value.
     */
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = y.toUint224() * Q112; // never overflows
    }

    /**
     * @dev Divides a UQ112x112 by a uint112, returning a UQ112x112.
     * @param x The numerator UQ112x112 value.
     * @param y The denominator uint112 value.
     * @return z The result of the division as a UQ112x112 value.
     */
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / y.toUint224();
    }
}
