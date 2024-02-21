// // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test, StdCheats } from "forge-std/Test.sol";
import "forge-std/console.sol";

import { RouterLib } from "../../src/libraries/RouterLib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract RouterLibTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;

    constructor() { }

    function setUp() public {
        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");
    }

    function test_ShouldBeSuccess_sortTokens() public {
        (address token0, address token1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));

        assertEq(token0, _token0);
        assertEq(token1, _token1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      REVERTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Revert_identicalAddresses_sortTokens() public {
        vm.expectRevert(RouterLib.IdenticalAddresses.selector);
        RouterLib.sortTokens(address(tokenA), address(tokenA));
    }

    function test_Revert_zeroAddress_sortTokens() public {
        vm.expectRevert(RouterLib.ZeroAddress.selector);
        RouterLib.sortTokens(address(tokenA), address(0));
    }
}
