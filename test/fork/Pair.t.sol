// // SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { stdError } from "forge-std/StdError.sol";

import { WETH } from "solady/tokens/WETH.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Pair } from "../../src/core/Pair.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { UQ112x112 } from "../../src/libraries/UQ112x112.sol";

import { MockFlashSwap } from "../mocks/MockFlashSwap.sol";

contract Pair_Fork_Test is Test {
    address public feeTo;
    address public feeToSetter;
    uint256 public token0Supply;
    uint256 public token1Supply;

    Pair internal pair;
    WETH internal weth;
    IERC20 internal chai;
    PairFactory internal pairFactory;

    //Ordered pair adress
    IERC20 public token0;
    WETH public token1;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function setUp() public {
        vm.createSelectFork({ urlOrAlias: "mainnet" });

        feeTo = makeAddr("feeTo");
        feeToSetter = makeAddr("feeToSetter");

        chai = IERC20(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
        weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

        pairFactory = new PairFactory(feeToSetter);

        address createdPairAddress = pairFactory.createPair(address(chai), address(weth));
        pair = Pair(createdPairAddress);

        (address _token0, address _token1) = RouterLib.sortTokens(address(chai), address(weth));
        token0 = IERC20(_token0);
        token1 = WETH(payable(_token1));

        token0Supply = token0.totalSupply();
        token1Supply = token1.totalSupply();

        vm.prank(0x12EDE161c702D1494612d19f05992f43aa6A26FB);
        token0.transfer(address(this), 10e18);

        token1.deposit{ value: 10e18 }();

        assertEq(pair.token0(), _token0);
        assertEq(pair.token1(), _token1);
        assertEq(pairFactory.getPair(_token0, _token1), createdPairAddress);
    }

    function test_ShouldBeSuccess_initialize() public {
        vm.prank(address(pairFactory));
        pair.initialize(address(token0), address(token1));

        assertEq(pair.token0(), address(token0));
        assertEq(pair.token1(), address(token1));
    }

    function test_ShouldBeSuccess_getReserves() public {
        (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) = pair.getReserves();

        assertEq(_reserve0, 0);
        assertEq(_reserve1, 0);
        assertEq(_blockTimestampLast, 0);
    }

    function test_ShouldBeSuccess_mint() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;

        token0.transfer(address(pair), token0transferAmount);
        token1.transfer(address(pair), token1transferAmount);

        uint256 expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
        uint256 actualLiquidity = Math.sqrt(token0transferAmount * token1transferAmount) - pair.MINIMUM_LIQUIDITY();

        uint256 poolBalanceToken0 = token0.balanceOf(address(pair));
        uint256 poolBalanceToken1 = token1.balanceOf(address(pair));

        vm.expectEmit(true, true, true, false);
        emit Mint(address(this), poolBalanceToken0 - 0, poolBalanceToken1 - 0);

        uint256 liquidity = pair.mint(address(this));

        assertEq(liquidity, actualLiquidity);
        assertEq(pair.totalSupply(), expectedLiquidity);
        assertEq(pair.balanceOf(address(this)), actualLiquidity);
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());

        assertEq(token0.balanceOf(address(pair)), token0transferAmount);
        assertEq(token1.balanceOf(address(pair)), token1transferAmount);

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_withLiquidity_mint() public {
        (uint256 firstExpectedLiquidity, uint256 firstActualLiquidity) = _addLiquidity(1e18, 1e18);

        vm.warp(block.timestamp + 37);
        pair.sync();

        uint256 token0TransferAmount = 2e18;
        uint256 token1TransferAmount = 2e18;

        token0.transfer(address(pair), token0TransferAmount);
        token1.transfer(address(pair), token1TransferAmount);

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        uint256 balance0 = token0.balanceOf(address(pair));
        uint256 balance1 = token1.balanceOf(address(pair));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 expectedLiquidity =
            Math.min((amount0 * pair.totalSupply()) / _reserve0, (amount1 * pair.totalSupply()) / _reserve1);

        uint256 liquidity = pair.mint(address(this));

        assertEq(liquidity, expectedLiquidity);
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalSupply(), (firstExpectedLiquidity + expectedLiquidity));
        assertEq(pair.balanceOf(address(this)), (firstActualLiquidity + expectedLiquidity));

        assertEq(token0.balanceOf(address(pair)), token0TransferAmount + 1e18);
        assertEq(token1.balanceOf(address(pair)), token1TransferAmount + 1e18);

        (_reserve0, _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_unbalanced_mint() public {
        (uint256 firstExpectedLiquidity, uint256 firstActualLiquidity) = _addLiquidity(1e18, 1e18);

        vm.warp(block.timestamp + 37);
        pair.sync();

        uint256 token0TransferAmount = 2e18;
        uint256 token1TransferAmount = 1e18;

        token0.transfer(address(pair), token0TransferAmount);
        token1.transfer(address(pair), token1TransferAmount);

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        uint256 balance0 = token0.balanceOf(address(pair));
        uint256 balance1 = token1.balanceOf(address(pair));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        uint256 expectedLiquidity =
            Math.min((amount0 * pair.totalSupply()) / _reserve0, (amount1 * pair.totalSupply()) / _reserve1);

        uint256 liquidity = pair.mint(address(this));

        assertEq(liquidity, expectedLiquidity);
        assertEq(pair.balanceOf(address(0)), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalSupply(), (firstExpectedLiquidity + expectedLiquidity));
        assertEq(pair.balanceOf(address(this)), (firstActualLiquidity + expectedLiquidity));

        assertEq(token0.balanceOf(address(pair)), token0TransferAmount + 1e18);
        assertEq(token1.balanceOf(address(pair)), token1TransferAmount + 1e18);

        (_reserve0, _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_burn() public {
        (, uint256 actualLiquidity) = _addLiquidity(1e18, 1e18);

        pair.transfer(address(pair), actualLiquidity);

        uint256 _totalSupply = pair.totalSupply();
        uint256 initialPoolBalanceToken0 = token0.balanceOf(address(pair));
        uint256 initialPoolBalanceToken1 = token1.balanceOf(address(pair));
        uint256 token0Amount = (actualLiquidity * initialPoolBalanceToken0) / _totalSupply;
        uint256 token1Amount = (actualLiquidity * initialPoolBalanceToken1) / _totalSupply;

        vm.expectEmit(true, true, true, true);
        emit Burn(address(this), token0Amount, token1Amount, address(this));

        pair.burn(address(this));

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);

        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(address(this)), 10e18 - 1e18 + token0Amount);
        assertEq(token1.balanceOf(address(this)), 10e18 - 1e18 + token1Amount);
    }

    function test_ShouldBeSuccess_swap() public {
        _addLiquidity(1e18, 2e18);

        uint256 swapAmountIn = 1e17;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, 1e18, 2e18);

        token0.transfer(address(pair), swapAmountIn);

        vm.expectEmit(true, true, true, true);
        emit Swap(address(this), swapAmountIn, 0, 0, amountOut, address(this));

        pair.swap(0, amountOut, address(this), "");

        assertEq(token0.balanceOf(address(this)), 10e18 - 1e18 - swapAmountIn);
        assertEq(token1.balanceOf(address(this)), 10e18 - 2e18 + amountOut);
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_reverse_swap() public {
        _addLiquidity(1e18, 2e18);

        uint256 swapAmountIn = 1e17;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, 2e18, 1e18);

        token1.transfer(address(pair), swapAmountIn);

        vm.expectEmit(true, true, true, true);
        emit Swap(address(this), 0, swapAmountIn, amountOut, 0, address(this));

        pair.swap(amountOut, 0, address(this), "");

        assertEq(token0.balanceOf(address(this)), 10e18 - 1e18 + amountOut);
        assertEq(token1.balanceOf(address(this)), 10e18 - 2e18 - swapAmountIn);
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_double_swap() public {
        _addLiquidity(1e18, 2e18);

        uint256 swapAmount0In = 1e17;
        uint256 amount0Out = RouterLib.getAmountOut(swapAmount0In, 1e18, 2e18);

        uint256 swapAmountIn = 1e17;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, 2e18, 1e18);

        token0.transfer(address(pair), swapAmount0In);
        token1.transfer(address(pair), swapAmountIn);

        vm.expectEmit(true, true, true, true);
        emit Swap(address(this), swapAmount0In, swapAmountIn, amountOut, amount0Out, address(this));

        pair.swap(amountOut, amount0Out, address(this), "");

        assertEq(token0.balanceOf(address(this)), 10e18 - 1e18 - swapAmount0In + amountOut);
        assertEq(token1.balanceOf(address(this)), 10e18 - 2e18 - swapAmountIn + amount0Out);
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_flashSwap() public {
        _addLiquidity(1e18, 2e18);

        uint256 flashSwapAmount = 1e17;
        uint256 flashSwapFee = (flashSwapAmount * 3) / 997 + 1;

        MockFlashSwap mockFlashSwap = new MockFlashSwap();

        token1.approve(address(mockFlashSwap), type(uint256).max);

        mockFlashSwap.flashSwap(address(pair), 0, flashSwapAmount, address(token1));

        assertEq(token1.balanceOf(address(mockFlashSwap)), 0);
        assertEq(token1.balanceOf(address(pair)), 2 ether + flashSwapFee);
    }

    function test_ShouldBeSuccess_reverse_flashSwap() public {
        _addLiquidity(2e18, 1e18);

        uint256 flashSwapAmount = 1e17;
        uint256 flashSwapFee = (flashSwapAmount * 3) / 997 + 1;

        MockFlashSwap mockFlashSwap = new MockFlashSwap();

        token0.approve(address(mockFlashSwap), type(uint256).max);

        mockFlashSwap.flashSwap(address(pair), flashSwapAmount, 0, address(token0));

        assertEq(token0.balanceOf(address(mockFlashSwap)), 0);
        assertEq(token0.balanceOf(address(pair)), 2 ether + flashSwapFee);
    }

    function test_ShouldBeSuccess_twap() public {
        vm.warp(0);
        _addLiquidity(1e18, 2e18);

        (uint256 initialPrice0, uint256 initialPrice1, uint32 expected) = _calculateCurrentPriceAndTime();

        vm.warp(2);
        pair.sync();

        assertEq(pair.price0CumulativeLast(), initialPrice0 * 2);
        assertEq(pair.price1CumulativeLast(), initialPrice1 * 2);

        (,, uint32 blockTimestampLast) = pair.getReserves();

        assertEq(expected + uint32(2), blockTimestampLast);
    }

    function test_ShouldBeSuccess_skim() public {
        _addLiquidity(1e18, 1e18);

        token0.transfer(address(pair), 1e18);
        token1.transfer(address(pair), 1e18);

        uint256 poolBalanceToken0 = token0.balanceOf(address(pair));
        uint256 poolBalanceToken1 = token1.balanceOf(address(pair));
        (uint112 _reserve0BeforeSync, uint112 _reserve1BeforeSync,) = pair.getReserves();

        assertNotEq(poolBalanceToken0, _reserve0BeforeSync);
        assertNotEq(poolBalanceToken1, _reserve1BeforeSync);

        pair.skim(address(this));

        (uint112 _reserve0AfterSync, uint112 _reserve1AfterSync,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0AfterSync);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1AfterSync);
    }

    function test_ShouldBeSuccess_sync() public {
        _addLiquidity(1e18, 1e18);

        token0.transfer(address(pair), 1e18);
        token1.transfer(address(pair), 1e18);

        uint256 poolBalanceToken0 = token0.balanceOf(address(pair));
        uint256 poolBalanceToken1 = token1.balanceOf(address(pair));
        (uint112 _reserve0BeforeSync, uint112 _reserve1BeforeSync,) = pair.getReserves();

        assertNotEq(poolBalanceToken0, _reserve0BeforeSync);
        assertNotEq(poolBalanceToken1, _reserve1BeforeSync);

        vm.expectEmit(true, true, false, false);
        emit Sync(_reserve0BeforeSync, _reserve1BeforeSync);

        pair.sync();

        (uint112 _reserve0AfterSync, uint112 _reserve1AfterSync,) = pair.getReserves();

        assertEq(poolBalanceToken0, _reserve0AfterSync);
        assertEq(poolBalanceToken1, _reserve1AfterSync);
    }

    function test_ShouldBeSuccess_mintFee() public {
        vm.prank(feeToSetter);
        pairFactory.setFeeTo(feeTo);

        (, uint256 actualLiquidity) = _addLiquidity(1e18, 1e18);

        uint256 swapAmountIn = 1e18;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, 1e18, 1e18);

        token1.transfer(address(pair), swapAmountIn);

        pair.swap(amountOut, 0, address(this), "");
        pair.transfer(address(pair), actualLiquidity);

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        uint256 feeLiquidity = _getMintFee(_reserve0, _reserve1);

        pair.burn(address(this));

        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY() + feeLiquidity);
        assertEq(pair.balanceOf(feeTo), feeLiquidity);

        (_reserve0, _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function test_ShouldBeSuccess_off_mintFee() public {
        vm.prank(feeToSetter);
        pairFactory.setFeeTo(feeTo);

        (, uint256 actualLiquidity) = _addLiquidity(1e18, 1e18);

        uint256 swapAmountIn = 1e18;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, 1e18, 1e18);

        token1.transfer(address(pair), swapAmountIn);

        pair.swap(amountOut, 0, address(this), "");
        pair.transfer(address(pair), actualLiquidity);

        vm.prank(feeToSetter);
        pairFactory.setFeeTo(address(0));

        pair.burn(address(this));

        assertEq(pair.kLast(), 0);
        assertEq(pair.balanceOf(feeTo), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      REVERTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Revert_Forbidden_initialize() public {
        vm.expectRevert(Pair.Forbidden.selector);
        pair.initialize(address(token0), address(token1));
    }

    function test_Revert_LiquidityUnderflow_mint() public {
        vm.expectRevert(stdError.arithmeticError);
        pair.mint(address(this));
    }

    function test_Revert_InsufficientLiquidityMinted_mint() public {
        token0.transfer(address(pair), 1000);
        token1.transfer(address(pair), 1000);

        vm.expectRevert(Pair.InsufficientLiquidityMinted.selector);
        pair.mint(address(this));
    }

    function test_Revert_ZeroTotalSupply_burn() public {
        vm.expectRevert(stdError.divisionError);
        pair.burn(address(this));
    }

    function test_Revert_InsufficientLiquidityBurned_burn() public {
        _addLiquidity(1e18, 1e18);

        vm.prank(address(0x1));
        vm.expectRevert(Pair.InsufficientLiquidityBurned.selector);
        pair.burn(address(this));
    }

    function test_Revert_InsufficientOutputAmount_swap() public {
        _addLiquidity(1e18, 1e18);

        vm.expectRevert(Pair.InsufficientOutputAmount.selector);
        pair.swap(0, 0, address(this), "");
    }

    function test_Revert_InsufficientLiquidity_swap() public {
        _addLiquidity(1e18, 1e18);

        vm.expectRevert(Pair.InsufficientLiquidity.selector);
        pair.swap(0, 5e18, address(this), "");
    }

    function test_Revert_InvalidTo_swap() public {
        _addLiquidity(1e18, 1e18);

        vm.expectRevert(Pair.InvalidTo.selector);
        pair.swap(0, 1e17, address(token0), "");
    }

    function test_Revert_InsufficientInputAmount_swap() public {
        _addLiquidity(1e18, 1e18);

        vm.expectRevert(Pair.InsufficientInputAmount.selector);
        pair.swap(0, 1e18, address(this), "");
    }

    function test_Revert_K_swap() public {
        _addLiquidity(1e18, 1e18);

        token0.transfer(address(pair), 1e17);

        vm.expectRevert(Pair.K.selector);
        pair.swap(0, 2e17, address(this), "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _addLiquidity(uint256 token0Amount, uint256 token1Amount) private returns (uint256, uint256) {
        uint256 expectedLiquidity = Math.sqrt(token0Amount * token1Amount);
        uint256 actualLiquidity = Math.sqrt(token0Amount * token1Amount) - pair.MINIMUM_LIQUIDITY();

        token0.transfer(address(pair), token0Amount);
        token1.transfer(address(pair), token1Amount);

        pair.mint(address(this));

        return (expectedLiquidity, actualLiquidity);
    }

    function _getMintFee(uint112 _reserve0, uint112 _reserve1) private view returns (uint256 liquidity) {
        uint256 _kLast = pair.kLast();

        if (_kLast != 0) {
            uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
            uint256 rootKLast = Math.sqrt(_kLast);

            if (rootK > rootKLast) {
                uint256 numerator = pair.totalSupply() * (rootK - rootKLast);
                uint256 denominator = (rootK * 5) + rootKLast;
                liquidity = numerator / denominator;
            }
        }
    }

    function _calculateCurrentPriceAndTime()
        private
        view
        returns (uint256 price0, uint256 price1, uint32 blockTimestamp)
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = pair.getReserves();
        blockTimestamp = blockTimestampLast;
        price0 = reserve0 > 0 ? (reserve1 * uint256(UQ112x112.Q112)) / reserve0 : 0;
        price1 = reserve1 > 0 ? (reserve0 * uint256(UQ112x112.Q112)) / reserve1 : 0;
    }
}
