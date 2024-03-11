// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { PairFactory } from "../src/core/PairFactory.sol";
import { Router } from "../src/helpers/Router.sol";
import { OrderManager } from "../src/utils/OrderManager.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { WETH } from "solady/tokens/WETH.sol";
import { RouterLib } from "./../src/libraries/RouterLib.sol";
import { console } from "forge-std/console.sol";

import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    uint8 public constant CHUNK_SIZE_LIMIT = 10;

    uint256 public deadline;

    receive() external payable { }

    function run()
        public
        broadcast
        returns (PairFactory factory, Router router, OrderManager orderManager, address mockPairAddress)
    {
        WETH weth;
        mockPairAddress = address(0);
        bool mocksEnabled =
            keccak256(abi.encodePacked(vm.envString("DEPLOY_MODE"))) == keccak256(abi.encodePacked(("test")));

        if (mocksEnabled) {
            weth = new WETH();
            weth.deposit{ value: 32e18 }();
        } else {
            weth = WETH(payable(vm.envAddress("WETH_ADDRESS")));
        }

        factory = new PairFactory(vm.envAddress("FEE_TO_SETTER"));
        router = new Router(address(factory), address(weth));
        orderManager = new OrderManager(address(factory), CHUNK_SIZE_LIMIT);

        orderManager.addExecutor(vm.envAddress("EXECUTOR"));

        if (mocksEnabled) {
            MockERC20 tokenA = new MockERC20("tokenA", "TA");
            MockERC20 tokenB = new MockERC20("tokenB", "TB");

            uint256 token0LiquidityAmt = 1_000_000e18;
            uint256 token1LiquidityAmt = 1_000_000e18;

            tokenA.approve(address(router), token0LiquidityAmt);
            tokenB.approve(address(router), token1LiquidityAmt);

            _addMockLiquidity(
                router,
                tokenA,
                tokenB,
                token0LiquidityAmt,
                token1LiquidityAmt,
                vm.envAddress("LIQUIDITY_TO"),
                block.timestamp + 1000
            );

            mockPairAddress = RouterLib.pairFor(address(factory), address(tokenA), address(tokenB));
        }
    }

    function _addMockLiquidity(
        Router _router,
        MockERC20 _tokenA,
        MockERC20 _tokenB,
        uint256 _tokenALiquidityAmount,
        uint256 _tokenBLiquidityAmount,
        address _liquidityTo,
        uint256 _deadline
    )
        private
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB, liquidity) = _router.addLiquidity(
            address(_tokenA),
            address(_tokenB),
            _tokenALiquidityAmount,
            _tokenBLiquidityAmount,
            _tokenALiquidityAmount,
            _tokenBLiquidityAmount,
            _liquidityTo,
            _deadline
        );
    }
}
