// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { Pair } from "../../src/core/Pair.sol";
import { Token } from "../../src/types/Token.sol";
import { Router } from "../../src/helpers/Router.sol";
import { WETH } from "solady/tokens/WETH.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract TokenTest is Test {
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    Router public router;
    PairFactory public pairFactory;
    WETH public weth;

    address[] public path;
    address public feeToSetter;
    uint256 public deadline;
    address public createdPairAddress;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        deadline = block.timestamp + 1;
        feeToSetter = makeAddr("feeToSetter");

        MockERC20 tokenA = new MockERC20("tokenA", "TA");
        MockERC20 tokenB = new MockERC20("tokenB", "TB");
        weth = new WETH();

        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));

        createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        path.push(address(token0));
        path.push(address(token1));
    }

    function test_ShouldBeSuccess_ComputePairAddress() public {
        address pairAddress =
            Token.wrap(address(token0)).computePairAddress(Token.wrap(address(token1)), address(pairFactory));

        assertEq(pairAddress, createdPairAddress);
    }

    function test_ShouldBeSuccess_CalculateAmounts() public {
        uint256 amountInAmount = 3e17;
        address path0Address = path[0];
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256[] memory amounts = new uint256[](2);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        (uint256 amountIn, uint256 amountOut) =
            Token.wrap(address(token0)).calculateAmounts(createdPairAddress, amountInAmount, path0Address);

        amounts = RouterLib.getAmountsOut(address(pairFactory), 3e17, path);

        assertEq(amountIn, amounts[0]);
        assertEq(amountOut, amounts[1]);
    }

    function test_ShouldBeSuccess_no_reserve_CalculateAmounts() public {
        uint256 amountInAmount = 3e17;
        address path0Address = path[0];

        (uint256 amountIn, uint256 amountOut) =
            Token.wrap(address(token0)).calculateAmounts(createdPairAddress, amountInAmount, path0Address);

        (uint256 reserve0, uint256 reserve1,) = Pair(createdPairAddress).getReserves();

        vm.expectRevert(RouterLib.InsufficientLiquidity.selector);
        RouterLib.getAmountOut(amountInAmount, reserve0, reserve1);

        assertEq(amountInAmount, amountIn);
        assertEq(amountOut, 0);
    }

    function test_ShouldBeSuccess_SafeTransferFrom() public {
        uint256 amountInAmount = 3e17;
        bool result;

        token0.approve(address(this), 3e17);
        result = Token.wrap(path[0]).transferFrom(address(this), createdPairAddress, amountInAmount);

        assertEq(token0.balanceOf(createdPairAddress), amountInAmount);
        assertEq(result, true);
    }

    function test_ShouldBeSuccess_invalid_SafeTransferFrom() public {
        bool result;
        uint256 amountInAmount = 3e17;
        address sender = makeAddr("sender");

        vm.startPrank(sender);
        token0.approve(address(this), 3e17);
        result = Token.wrap(path[0]).transferFrom(address(this), createdPairAddress, amountInAmount);

        assertEq(result, false);
    }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       HELPERS
    //     ////////////////////////////////////////////////////////////////////////*/

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
