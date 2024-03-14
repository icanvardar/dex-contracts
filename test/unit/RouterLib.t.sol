// // SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { Router } from "../../src/helpers/Router.sol";
import { WETH } from "solady/tokens/WETH.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { Pair } from "../../src/core/Pair.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract RouterLibTest is Test {
    uint256 public deadline;
    address public feeToSetter;
    address public createdPairAddress;

    Pair internal pair;
    WETH public weth;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    Router public router;
    PairFactory public pairFactory;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        deadline = block.timestamp + 1;
        feeToSetter = makeAddr("feeToSetter");

        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");
        weth = new WETH();

        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));

        createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));
        pair = Pair(createdPairAddress);

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
    }

    function test_ShouldBeSuccess_sortTokens() public {
        (address tok0, address tok1) = sort(address(tokenA), address(tokenB));
        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));

        assertEq(tok0, _token0);
        assertEq(tok1, _token1);
    }

    function test_ShouldBeSuccess_PairFor() public {
        address pairAddress = RouterLib.pairFor(address(pairFactory), address(tokenA), address(tokenB));

        assertEq(pairAddress, createdPairAddress);
    }

    function test_ShouldBeSuccess_GetReserves() public {
        (uint256 reserveA, uint256 reserveB) =
            RouterLib.getReserves(address(pairFactory), address(tokenA), address(tokenB));

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(reserveA, uint256(_reserve0));
        assertEq(reserveB, uint256(_reserve1));
    }

    function test_ShouldBeSuccess_Quote() public {
        uint256 amountA = 1e18;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        uint256 amountB = RouterLib.quote(amountA, reserveA, reserveB);

        _addLiquidity(1e18, 1e18);

        (uint256 _reserve0, uint256 _reserve1,) = pair.getReserves();

        uint256 amountOutToken = (_reserve0 * amountA) / _reserve1;

        assertEq(amountB, amountOutToken);
    }

    function test_ShouldBeSuccess_GetAmountOut() public {
        uint256 amountIn = 3e17;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        _addLiquidity(reserveA, reserveB);

        token0.approve(address(router), reserveA);
        token1.approve(address(router), reserveB);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256 amountOut = RouterLib.getAmountOut(amountIn, reserveA, reserveB);

        token0.approve(address(router), 3e17);
        uint256[] memory amounts = router.swapExactTokensForTokens(3e17, 1e17, path, address(this), deadline);

        assertEq(amountOut, amounts[1]);
    }

    function test_ShouldBeSuccess_GetAmountIn() public {
        uint256 amountOut = 3e17;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        _addLiquidity(reserveA, reserveB);

        token0.approve(address(router), reserveA);
        token1.approve(address(router), reserveB);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256 amountIn = RouterLib.getAmountIn(amountOut, reserveA, reserveB);

        token0.approve(address(router), amountIn);
        uint256[] memory amounts = router.swapTokensForExactTokens(3e17, 10e17, path, address(this), deadline);

        assertEq(amountIn, amounts[0]);
    }

    function test_ShouldBeSuccess_GetAmountsOut() public {
        uint256 amountIn = 3e17;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        _addLiquidity(reserveA, reserveB);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256[] memory amounts = RouterLib.getAmountsOut(address(pairFactory), amountIn, path);

        uint256 amountOut = RouterLib.getAmountOut(amountIn, reserveA, reserveB);

        assertEq(amountOut, amounts[1]);
    }

    function test_ShouldBeSuccess_GetAmountsIn() public {
        uint256 amountOut = 3e17;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        _addLiquidity(reserveA, reserveB);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256[] memory amounts = RouterLib.getAmountsIn(address(pairFactory), amountOut, path);

        uint256 amountIn = RouterLib.getAmountIn(amountOut, reserveA, reserveB);

        assertEq(amountIn, amounts[0]);
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

    function test_Revert_insufficientAmount_Quote() public {
        uint256 amountA = 0;
        uint256 reserveA = 1e18;
        uint256 reserveB = 1e18;

        vm.expectRevert(RouterLib.InsufficientAmount.selector);
        RouterLib.quote(amountA, reserveA, reserveB);
    }

    function test_Revert_insufficientLiquidity_Quote() public {
        uint256 amountA = 3e18;
        uint256 reserveA = 0;
        uint256 reserveB = 0;

        vm.expectRevert(RouterLib.InsufficientLiquidity.selector);
        RouterLib.quote(amountA, reserveA, reserveB);
    }

    function test_Revert_insufficientInputAmount_GetAmountOut() public {
        uint256 amountA = 0;
        uint256 reserveA = 0;
        uint256 reserveB = 0;

        vm.expectRevert(RouterLib.InsufficientInputAmount.selector);
        RouterLib.getAmountOut(amountA, reserveA, reserveB);
    }

    function test_Revert_insufficientLiquidity_GetAmountOut() public {
        uint256 amountA = 1e18;
        uint256 reserveA = 0;
        uint256 reserveB = 0;

        vm.expectRevert(RouterLib.InsufficientLiquidity.selector);
        RouterLib.getAmountOut(amountA, reserveA, reserveB);
    }

    function test_Revert_insufficientOutputAmount_GetAmountIn() public {
        uint256 amountA = 0;
        uint256 reserveA = 0;
        uint256 reserveB = 0;

        vm.expectRevert(RouterLib.InsufficientOutputAmount.selector);
        RouterLib.getAmountIn(amountA, reserveA, reserveB);
    }

    function test_Revert_insufficientLiquidity_GetAmountIn() public {
        uint256 amountA = 1e18;
        uint256 reserveA = 0;
        uint256 reserveB = 0;

        vm.expectRevert(RouterLib.InsufficientLiquidity.selector);
        RouterLib.getAmountIn(amountA, reserveA, reserveB);
    }

    function test_Revert_invalidPath_GetAmountsOut() public {
        uint256 amountIn = 1e18;
        address[] memory path = new address[](1);

        vm.expectRevert(RouterLib.InvalidPath.selector);
        RouterLib.getAmountsOut(address(pairFactory), amountIn, path);
    }

    function test_Revert_invalidPath_GetAmountsIn() public {
        uint256 amountOut = 1e18;
        address[] memory path = new address[](1);

        vm.expectRevert(RouterLib.InvalidPath.selector);
        RouterLib.getAmountsIn(address(pairFactory), amountOut, path);
    }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       HELPERS
    //     ////////////////////////////////////////////////////////////////////////*/

    function sort(
        address token0Addr,
        address token1Addr
    )
        private
        pure
        returns (address _currency0, address _currency1)
    {
        if (address(token0Addr) < address(token1Addr)) {
            (_currency0, _currency1) = (token0Addr, token1Addr);
        } else {
            (_currency0, _currency1) = (token1Addr, token0Addr);
        }
    }

    function _addLiquidity(
        uint256 _token0Amount,
        uint256 _token1Amount
    )
        private
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        token0.approve(address(router), _token0Amount);
        token1.approve(address(router), _token1Amount);
        (amountA, amountB, liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            _token0Amount,
            _token1Amount,
            _token0Amount,
            _token1Amount,
            address(this),
            deadline
        );
    }
}
