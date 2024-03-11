// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { UQ112x112 } from "../../src/libraries/UQ112x112.sol";

import { SafeCastLib } from "solady/utils/SafeCastLib.sol";

contract UQ112x112FuzzTest is Test {
    using SafeCastLib for uint112;

    function test_ShouldBeSuccess_Encode(uint112 value) public {
        uint224 encoded = UQ112x112.encode(value);

        assertEq(encoded / UQ112x112.Q112, value);
    }

    function test_uqdiv(uint224 x, uint112 y) public {
        vm.assume(y > 0);

        uint224 expected = x / y.toUint224();

        uint224 actual = UQ112x112.uqdiv(x, y);

        assertEq(actual, expected);
    }
}
