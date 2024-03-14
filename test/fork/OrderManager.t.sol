// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { WETH } from "solady/tokens/WETH.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { Pair } from "../../src/core/Pair.sol";
import { Router } from "../../src/helpers/Router.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { OrderManager } from "../../src/utils/OrderManager.sol";
import { ExecutionCall, ExecutionResult, Order, OrderLibrary } from "../../src/types/Order.sol";

contract OrderManager_Fork_Test is Test {
    uint256 public constant TOKEN_A_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint256 public constant TOKEN_B_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint8 public constant CHUNK_SIZE_LIMIT = 2;
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    address public web2Service;
    address public feeToSetter;
    uint256 public token0Supply;
    uint256 public token1Supply;

    Pair public pair;
    WETH public weth;
    IERC20 public chai;
    Router public router;
    PairFactory public pairFactory;
    OrderManager public orderManager;

    //Ordered pair adress
    IERC20 public token0;
    WETH public token1;

    function setUp() public {
        vm.createSelectFork({ urlOrAlias: "mainnet" });

        feeToSetter = makeAddr("feeToSetter");
        web2Service = makeAddr("web2Service");

        chai = IERC20(0x06AF07097C9Eeb7fD685c692751D5C66dB49c215);
        weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));

        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));
        orderManager = new OrderManager(address(pairFactory), CHUNK_SIZE_LIMIT);

        orderManager.addExecutor(address(this));

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

        assertEq(token0.balanceOf(address(this)), 10e18);
        assertEq(token1.balanceOf(address(this)), 10e18);
    }

    function test_ShouldBeSuccess_Initialize() public {
        OrderManager orderManagerTest = new OrderManager(address(pairFactory), CHUNK_SIZE_LIMIT);

        assertEq(orderManagerTest.FACTORY(), address(pairFactory));
        assertEq(orderManagerTest.CHUNK_SIZE_LIMIT(), CHUNK_SIZE_LIMIT);
        assertEq(orderManagerTest.owner(), address(this));
    }

    function test_ShouldBeSuccess_BatchExecuteOrder() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 5e18;

        ExecutionCall[] memory executionCalls = new ExecutionCall[](1);
        ExecutionResult[] memory results = new ExecutionResult[](executionCalls.length);

        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order =
            Order(3e17, 1e17, path, senderAddress, senderAddress, block.timestamp + 10, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManager), block.chainid);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        executionCalls[0] = ExecutionCall(order, signature);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token0.transfer(senderAddress, senderAddressAmount);

        vm.prank(senderAddress);
        token0.approve(address(orderManager), 6e17);

        uint256 amountOut = RouterLib.getAmountOut(3e17, 1e18, 1e18);

        results = orderManager.batchExecuteOrder(executionCalls);

        for (uint256 i = 0; i < results.length; i++) {
            assertEq(results[i].success, true);
        }

        assertEq(token0.balanceOf(address(this)), 10e18 - 1e18 - senderAddressAmount);

        assertEq(token0.balanceOf(senderAddress), senderAddressAmount - 3e17);
        assertEq(token1.balanceOf(senderAddress), amountOut);

        assertEq(token0.balanceOf(address(pair)), 1e18 + 3e17);
        assertEq(token1.balanceOf(address(pair)), 1e18 - amountOut);
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
            block.timestamp + 10
        );
    }

    function _getDomainSeperator(address contractAdress, uint256 chainId) private pure returns (bytes32 separator) {
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 nameHash = keccak256(bytes("OrderManager"));

        assembly {
            let m := mload(0x40)
            mstore(m, _DOMAIN_TYPEHASH)
            mstore(add(m, 0x20), nameHash)
            mstore(add(m, 0x40), versionHash)
            mstore(add(m, 0x60), chainId)
            mstore(add(m, 0x80), contractAdress)
            separator := keccak256(m, 0xa0)
        }
    }

    function _getPermitHash(
        Order memory order,
        address contractAdress,
        uint256 chainId
    )
        private
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _getDomainSeperator(contractAdress, chainId),
                keccak256(
                    abi.encode(
                        OrderLibrary.ORDER_TYPEHASH,
                        order.amountIn,
                        order.amountOutMin,
                        keccak256(abi.encodePacked(order.path)),
                        order.from,
                        order.to,
                        order.deadline,
                        order.timestamp
                    )
                )
            )
        );
    }
}
