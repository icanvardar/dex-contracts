// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { UQ112x112 } from "../../src/libraries/UQ112x112.sol";

contract UQ112x112Test is Test {
    function test_ShouldBeSuccess_Encode(uint112 value) public {
        uint224 encoded = UQ112x112.encode(value);

        assertEq(encoded / UQ112x112.Q112, value);
    }

    // function test_ShouldBeSuccess_Uqdiv(uint256 _value, uint256 _denominator) public {
    //     uint256 value = bound(_value, 1, 2 ** 112 - 1);
    //     uint256 denominator = bound(_denominator, 0, 2 ** 112 - 1);

    //     uint224 encoded = UQ112x112.encode(uint112(value));
    //     uint224 divided = UQ112x112.uqdiv(encoded, uint112(denominator));

    //     assertEq(divided * UQ112x112.encode(uint112(denominator)), encoded);
    // }
}
