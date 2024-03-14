// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { LPToken } from "../../src/core/LPToken.sol";

contract LPTokenTest is Test {
    LPToken internal lpToken;

    function setUp() public {
        lpToken = new LPToken();
    }

    function test_ShouldBeSuccess_initialize() public {
        lpToken = new LPToken();

        assertEq(lpToken.name(), "Dex LP Token");
        assertEq(lpToken.symbol(), "DLPT");
    }
}
