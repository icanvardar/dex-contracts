// SPDX-License-Identifier: MIT
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
    struct DeploymentResult {
        address factory;
        address router;
        address orderManager;
        address weth;
        address[] mockPairs;
    }

    PairFactory public factory;
    Router public router;
    OrderManager public orderManager;
    WETH public weth;
    address[] public mockPairs;

    receive() external payable { }

    function run() public broadcast returns (DeploymentResult memory deploymentResult) {
        string memory deployMode;

        try vm.envString("DEPLOY_MODE") returns (string memory mode) {
            deployMode = mode;
        } catch {
            console.log("DEPLOY_MODE variable not found, automatically switched to production mode!");
        }

        bool mocksEnabled = keccak256(abi.encodePacked(deployMode)) == keccak256(abi.encodePacked(("test")));

        uint8 chunkSizeLimit = uint8(vm.envUint("CHUNK_SIZE_LIMIT"));

        if (mocksEnabled) {
            weth = new WETH();
            weth.deposit{ value: 32e18 }();
        } else {
            weth = WETH(payable(vm.envAddress("WETH_ADDRESS")));
        }

        factory = new PairFactory(vm.envAddress("FEE_TO_SETTER"));
        router = new Router(address(factory), address(weth));
        orderManager = new OrderManager(address(factory), chunkSizeLimit);

        orderManager.addExecutor(vm.envAddress("EXECUTOR"));

        if (mocksEnabled) {
            MockERC20 mockUsdt = new MockERC20("MockUSDT", "MUSDT");
            MockERC20 mockDai = new MockERC20("MockDAI", "MDAI");

            uint256 mockUsdtLiquidityAmt = 132_000e18;
            uint256 mockDaiLiquidityAmt = 132_000e18;
            uint256 wethLiquidityAmt = 32e18;

            // MockUSDT MockDAI 100_000 100_000
            // WETH MockUSDT 16 32_000
            // WETH MockDAI 16 32_000

            mockUsdt.approve(address(router), mockUsdtLiquidityAmt);
            mockDai.approve(address(router), mockDaiLiquidityAmt);
            weth.approve(address(router), wethLiquidityAmt);

            address[2] memory firstPairAssets = [address(mockUsdt), address(mockDai)];
            address[2] memory secondPairAssets = [address(weth), address(mockUsdt)];
            address[2] memory thirdPairAssets = [address(weth), address(mockDai)];

            address[2][3] memory pairAssets = [firstPairAssets, secondPairAssets, thirdPairAssets];

            uint256[2] memory firstPairAmts = [uint256(100_000e18), uint256(100_000e18)];
            uint256[2] memory secondPairAmts = [uint256(16e18), uint256(32_000e18)];
            uint256[2] memory thirdPairAmts = [uint256(16e18), uint256(32_000e18)];

            uint256[2][3] memory pairAmts = [firstPairAmts, secondPairAmts, thirdPairAmts];

            uint8 i = 0;
            for (i; i < pairAssets.length; i++) {
                address tokenA = pairAssets[i][0];
                address tokenB = pairAssets[i][1];
                uint256 tokenAAmt = pairAmts[i][0];
                uint256 tokenBAmt = pairAmts[i][1];

                address mockPairAddress = _addMockLiquidity(
                    router, tokenA, tokenB, tokenAAmt, tokenBAmt, vm.envAddress("LIQUIDITY_TO"), block.timestamp + 1000
                );
                mockPairs.push(mockPairAddress);
            }
        }

        deploymentResult.factory = address(factory);
        deploymentResult.router = address(router);
        deploymentResult.orderManager = address(orderManager);
        deploymentResult.weth = address(weth);
        deploymentResult.mockPairs = mockPairs;
    }

    function _addMockLiquidity(
        Router _router,
        address _tokenA,
        address _tokenB,
        uint256 _tokenALiquidityAmount,
        uint256 _tokenBLiquidityAmount,
        address _liquidityTo,
        uint256 _deadline
    )
        private
        returns (address pairAddress)
    {
        _router.addLiquidity(
            _tokenA,
            _tokenB,
            _tokenALiquidityAmount,
            _tokenBLiquidityAmount,
            _tokenALiquidityAmount,
            _tokenBLiquidityAmount,
            _liquidityTo,
            _deadline
        );

        pairAddress = RouterLib.pairFor(address(factory), address(_tokenA), address(_tokenB));
    }
}
