//SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import { stdError } from "forge-std/StdError.sol";

import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { Pair } from "../../src/core/Pair.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { UQ112x112 } from "../../src/libraries/UQ112x112.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { MockFlashSwap } from "../mocks/MockFlashSwap.sol";

contract PairFuzzTest is Test {
    uint256 public constant TOKEN_A_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint256 public constant TOKEN_B_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;

    uint256 private constant UINT112_TOKEN_A_MAX_TOKENS = 5_192_296_858_534_827e18;
    uint256 private constant UINT112_TOKEN_B_MAX_TOKENS = 5_192_296_858_534_827e18;

    address public feeToSetter;
    address public feeTo;

    Pair pair;
    MockERC20 tokenA;
    MockERC20 tokenB;
    PairFactory pairFactory;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

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

    constructor() { }

    function setUp() public {
        feeTo = makeAddr("feeTo");
        feeToSetter = makeAddr("feeToSetter");

        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");

        pairFactory = new PairFactory(feeToSetter);

        address createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));
        pair = Pair(createdPairAddress);

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        assertEq(pair.token0(), _token0);
        assertEq(pair.token1(), _token1);
        assertEq(pairFactory.getPair(_token0, _token1), createdPairAddress);
    }

    function testFuzz_ShouldBeSuccess_mint(uint256 token0Count, uint256 token1Count) public {
        uint256 token0transferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS);
        uint256 token1transferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS);

        token0.transfer(address(pair), token0transferAmount);
        token1.transfer(address(pair), token1transferAmount);

        uint256 expectedLiquidity = Math.sqrt(token0transferAmount * token1transferAmount);
        uint256 actualLiquidity = Math.sqrt(token0transferAmount * token1transferAmount) - pair.MINIMUM_LIQUIDITY();

        uint256 poolBalanceToken0 = token0.balanceOf(address(pair));
        uint256 poolBalanceToken1 = token1.balanceOf(address(pair));

        vm.expectEmit(true, true, true, false);
        emit Mint(address(this), poolBalanceToken0, poolBalanceToken1);

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

    function testFuzz_ShouldBeSuccess_withLiquidity_mint(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        (uint256 firstExpectedLiquidity, uint256 firstActualLiquidity) = _addLiquidity(1e18, 1e18);

        vm.warp(block.timestamp + 37);
        pair.sync();

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

    function testFuzz_ShouldBeSuccess_burn(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS);

        (, uint256 actualLiquidity) = _addLiquidity(token0TransferAmount, token1TransferAmount);

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
        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - token0TransferAmount + token0Amount);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - token1TransferAmount + token1Amount);
    }

    function testFuzz_ShouldBeSuccess_swap(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        uint256 swapAmountIn = 1e17;
        uint256 amountOut = RouterLib.getAmountOut(swapAmountIn, token0TransferAmount, token1TransferAmount);

        token0.transfer(address(pair), swapAmountIn);

        vm.expectEmit(true, true, true, true);
        emit Swap(address(this), swapAmountIn, 0, 0, amountOut, address(this));

        pair.swap(0, amountOut, address(this), "");

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - token0TransferAmount - swapAmountIn);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - token1TransferAmount + amountOut);
        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function testFuzz_ShouldBeSuccess_flashSwap(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        uint256 flashSwapAmount = 1e17;
        uint256 flashSwapFee = (flashSwapAmount * 3) / 997 + 1;

        MockFlashSwap mockFlashSwap = new MockFlashSwap();

        token1.approve(address(mockFlashSwap), type(uint256).max);

        mockFlashSwap.flashSwap(address(pair), 0, flashSwapAmount, address(token1));

        assertEq(token1.balanceOf(address(mockFlashSwap)), 0);
        assertEq(token1.balanceOf(address(pair)), token1TransferAmount + flashSwapFee);
    }

    function testFuzz_ShouldBeSuccess_twap(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        vm.warp(0);
        _addLiquidity(token0TransferAmount, token1TransferAmount);

        (uint256 initialPrice0, uint256 initialPrice1, uint32 expected) = _calculateCurrentPriceAndTime();

        vm.warp(2);
        pair.sync();

        assertEq(pair.price0CumulativeLast(), initialPrice0 * 2);
        assertEq(pair.price1CumulativeLast(), initialPrice1 * 2);

        (,, uint32 blockTimestampLast) = pair.getReserves();

        assertEq(expected + uint32(2), blockTimestampLast);
    }

    function testFuzz_ShouldBeSuccess_skim(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

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

    function testFuzz_ShouldBeSuccess_sync(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

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

    function testFuzz_ShouldBeSuccess_mintFee(address _feeTo) public {
        vm.assume(_feeTo != address(this));
        vm.assume(_feeTo != address(0));

        vm.prank(feeToSetter);
        pairFactory.setFeeTo(_feeTo);

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
        assertEq(pair.balanceOf(_feeTo), feeLiquidity);

        (_reserve0, _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    function testFuzz_ShouldBeSuccess_off_mintFee(address _feeTo) public {
        vm.assume(_feeTo != address(this));
        vm.assume(_feeTo != address(0));

        vm.prank(feeToSetter);
        pairFactory.setFeeTo(_feeTo);

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
        assertEq(pair.balanceOf(_feeTo), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();

        assertEq(uint112(token0.balanceOf(address(pair))), _reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), _reserve1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      REVERTS
    ////////////////////////////////////////////////////////////////////////*/

    function testFuzz_Revert_InsufficientLiquidityMinted_mint(uint256 token0Count, uint256 token1Count) public {
        uint256 token0TransferAmount = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS / 2);
        uint256 token1TransferAmount = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS / 2);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        vm.expectRevert(Pair.InsufficientLiquidityMinted.selector);
        pair.mint(address(this));
    }

    function testFuzz_Revert_InsufficientLiquidityBurned_Burn(uint256 token0Count, uint256 token1Count) public {
        token0Count = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS);
        token1Count = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS);

        _addLiquidity(token0Count, token1Count);

        vm.expectRevert(Pair.InsufficientLiquidityBurned.selector);
        pair.burn(address(this));
    }

    function testFuzz_Revert_InsufficientLiquidity_swap(uint256 token0Count, uint256 token1Count) public {
        token0Count = bound(token0Count, 1e18, UINT112_TOKEN_A_MAX_TOKENS);
        token1Count = bound(token1Count, 1e18, UINT112_TOKEN_B_MAX_TOKENS);
        _addLiquidity(token0Count, token1Count);

        vm.expectRevert(Pair.InsufficientLiquidity.selector);
        pair.swap(0, token1Count + 1e18, address(this), "");
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    ////////////////////////////////////////////////////////////////////////*/

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
