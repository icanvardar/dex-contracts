// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { LPToken } from "../../src/core/LPToken.sol";

contract LPTokenTest is Test {
    LPToken lpToken;

    constructor() { }

    function setUp() public {
        lpToken = new LPToken();
    }

    function test_ShouldBeSuccess_initialize() public {
        lpToken = new LPToken();

        assertEq(lpToken.name(), "Dex LP Token");
        assertEq(lpToken.symbol(), "DLPT");
    }
}
