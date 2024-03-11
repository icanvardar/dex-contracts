// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { IPair } from "../../src/interfaces/IPair.sol";

import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract PairFactoryTest is Test {
    address public owner;
    address public feeTo;

    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    PairFactory internal pairFactory;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function setUp() public {
        owner = makeAddr("owner");
        feeTo = makeAddr("feeTo");

        vm.startPrank(owner);

        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");
        pairFactory = new PairFactory(owner);

        vm.stopPrank();
    }

    function test_ShouldBeSuccess_allPairsLength() public {
        pairFactory.createPair(address(tokenA), address(tokenB));

        assertEq(pairFactory.allPairsLength(), 1);
    }

    function test_ShouldBeSuccess_createPair() public {
        (address _tokenA, address _tokenB) = RouterLib.sortTokens(address(tokenA), address(tokenB));

        address pairAddress = RouterLib.pairFor(address(pairFactory), address(tokenA), address(tokenB));

        vm.expectEmit(true, true, true, true);
        emit PairCreated(_tokenA, _tokenB, pairAddress, 1);
        address createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));

        assertEq(pairFactory.allPairsLength(), 1);
        assertEq(pairAddress, createdPairAddress);
        assertEq(IPair(pairAddress).token0(), _tokenA);
        assertEq(IPair(pairAddress).token1(), _tokenB);
        assertEq(pairFactory.allPairs(0), createdPairAddress);
        assertEq(pairFactory.getPair(address(tokenA), address(tokenB)), createdPairAddress);
        assertEq(pairFactory.getPair(address(tokenB), address(tokenA)), createdPairAddress);
    }

    function test_ShouldBeSuccess_setFeeTo() public {
        vm.prank(owner);
        pairFactory.setFeeTo(feeTo);

        assertEq(pairFactory.feeTo(), feeTo);
    }

    function test_ShouldBeSuccess_setFeeToSetter() public {
        vm.prank(owner);
        pairFactory.setFeeToSetter(feeTo);

        assertEq(pairFactory.feeToSetter(), feeTo);
    }

    function test_Revert_IdenticalAddresses_createPair() public {
        vm.expectRevert(PairFactory.IdenticalAddresses.selector);
        pairFactory.createPair(address(tokenA), address(tokenA));
    }

    function test_Revert_ZeroAddress_createPair() public {
        vm.expectRevert(PairFactory.ZeroAddress.selector);
        pairFactory.createPair(address(0), address(tokenA));
    }

    function test_Revert_PairExists_createPair() public {
        pairFactory.createPair(address(tokenA), address(tokenB));

        vm.expectRevert(PairFactory.PairExists.selector);
        pairFactory.createPair(address(tokenA), address(tokenB));
    }

    function test_Revert_Forbidden_setFeeTo() public {
        vm.expectRevert(PairFactory.Forbidden.selector);
        pairFactory.setFeeTo(feeTo);
    }

    function test_Revert_Forbidden_setFeeToSetter() public {
        vm.expectRevert(PairFactory.Forbidden.selector);
        pairFactory.setFeeToSetter(feeTo);
    }
}
