// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { WETH } from "solady/tokens/WETH.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import { Pair } from "../../../src/core/Pair.sol";
import { Router } from "../../../src/helpers/Router.sol";
import { PairFactory } from "../../../src/core/PairFactory.sol";
import { RouterLib } from "../../../src/libraries/RouterLib.sol";
import { OrderManager } from "../../../src/utils/OrderManager.sol";
import { ExecutionCall, ExecutionResult, Order, OrderLibrary } from "../../../src/types/Order.sol";

import { MockERC20 } from "../../mocks/MockERC20.sol";

contract BatchExecuteOrder_Integration_Test is Test {
    uint256 public constant TOKEN_A_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint256 public constant TOKEN_B_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint8 public constant CHUNK_SIZE_LIMIT = 2;
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    address public web2Service;
    uint256 public deadline;
    address public feeToSetter;

    Pair public pair;
    WETH public weth;
    Router public router;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    PairFactory public pairFactory;
    OrderManager public orderManager;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    event OrderExecuted(
        uint256 amountIn, uint256 amountOutMin, address[] indexed path, address indexed from, address to
    );

    event ExecutorAdded(address serviceAddress);
    event ExecutorRemoved(address serviceAddress);

    constructor() { }

    function setUp() public {
        deadline = block.timestamp + 1;
        feeToSetter = makeAddr("feeToSetter");
        web2Service = makeAddr("web2Service");

        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");
        weth = new WETH();

        weth.deposit{ value: 20e18 }();

        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));
        orderManager = new OrderManager(address(pairFactory), CHUNK_SIZE_LIMIT);

        orderManager.addExecutor(web2Service);

        address createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));
        pair = Pair(createdPairAddress);

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        assertEq(pair.token0(), _token0);
        assertEq(pair.token1(), _token1);
        assertEq(pairFactory.getPair(_token0, _token1), createdPairAddress);
    }

    function test_ShouldBeSuccess_Initialize() public {
        orderManager = new OrderManager(address(pairFactory), CHUNK_SIZE_LIMIT);

        assertEq(orderManager.FACTORY(), address(pairFactory));
        assertEq(orderManager.CHUNK_SIZE_LIMIT(), CHUNK_SIZE_LIMIT);
        assertEq(orderManager.owner(), address(this));
    }

    function test_ShouldBeSuccess_pair_interaction_BatchExecuteOrder() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 10e18;

        ExecutionCall[] memory executionCalls = new ExecutionCall[](1);
        ExecutionResult[] memory results = new ExecutionResult[](executionCalls.length);

        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManager));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        executionCalls[0] = ExecutionCall(order, signature);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token0.transfer(senderAddress, senderAddressAmount);

        vm.prank(senderAddress);
        token0.approve(address(orderManager), 6e17);

        uint256 amountOut = RouterLib.getAmountOut(3e17, 1e18, 1e18);

        uint256 pairBalance0 = token0.balanceOf(address(pair));
        uint256 pairBalance1 = token1.balanceOf(address(pair));

        vm.prank(web2Service);
        results = orderManager.batchExecuteOrder(executionCalls);

        uint256 actualPairBalance0 = token0.balanceOf(address(pair));
        uint256 actualPairBalance1 = token1.balanceOf(address(pair));

        uint256 expectedPairBalance0 = pairBalance0 + 3e17;
        uint256 expectedPairBalance1 = pairBalance1 - amountOut;

        assertEq(actualPairBalance0, expectedPairBalance0);
        assertEq(actualPairBalance1, expectedPairBalance1);
    }

    function test_ShouldBeSuccess_user_interaction_userBatchExecuteOrder() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 10e18;

        ExecutionCall[] memory executionCalls = new ExecutionCall[](1);
        ExecutionResult[] memory results = new ExecutionResult[](executionCalls.length);

        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManager));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        executionCalls[0] = ExecutionCall(order, signature);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token0.transfer(senderAddress, senderAddressAmount);

        vm.prank(senderAddress);
        token0.approve(address(orderManager), 6e17);

        uint256 amountOut = RouterLib.getAmountOut(3e17, 1e18, 1e18);

        uint256 senderBalance0 = token0.balanceOf(address(senderAddress));
        uint256 senderBalance1 = token1.balanceOf(address(senderAddress));

        vm.prank(web2Service);
        results = orderManager.batchExecuteOrder(executionCalls);

        uint256 actualSenderBalance0 = token0.balanceOf(address(senderAddress));
        uint256 actualSenderBalance1 = token1.balanceOf(address(senderAddress));

        uint256 expectedSenderBalance0 = senderBalance0 - 3e17;
        uint256 expectedSenderBalance1 = senderBalance1 + amountOut;

        assertEq(actualSenderBalance0, expectedSenderBalance0);
        assertEq(actualSenderBalance1, expectedSenderBalance1);
    }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       REVERTS
    //     ////////////////////////////////////////////////////////////////////////*/

    function test_RevertWhen_emptyOrdersNotSupported() public {
        ExecutionCall[] memory ExecutionCalls = new ExecutionCall[](0);

        vm.prank(web2Service);
        vm.expectRevert(OrderManager.EmptyOrdersNotSupported.selector);
        orderManager.batchExecuteOrder(ExecutionCalls);
    }

    function test_RevertWhen_chunkSizeExceeded() public {
        address senderAddress = vm.addr(1);
        bytes[] memory signatures = new bytes[](3);
        address[][] memory paths = new address[][](1);
        Order[] memory orders = new Order[](3);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        paths[0] = new address[](2);

        paths[0][0] = address(token0);
        paths[0][1] = address(token1);

        orders[0] = Order(3e17, 1e17, paths[0], senderAddress, senderAddress, deadline, block.timestamp);
        orders[1] = Order(amount1Out, amount2Out, paths[0], senderAddress, senderAddress, deadline, block.timestamp);
        orders[2] = Order(amount1Out, amount2Out, paths[0], senderAddress, senderAddress, deadline, block.timestamp);

        for (uint256 i; i < signatures.length; i++) {
            bytes32 permitMeesageHash = _getPermitHash(orders[i], address(orderManager));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
            signatures[i] = abi.encodePacked(r, s, v);
        }

        ExecutionCall[] memory executionCalls = new ExecutionCall[](signatures.length);

        for (uint256 i; i < signatures.length; i++) {
            executionCalls[i] = ExecutionCall(orders[i], signatures[i]);
        }

        vm.prank(web2Service);
        vm.expectRevert(OrderManager.ChunkSizeExceeded.selector);
        orderManager.batchExecuteOrder(executionCalls);
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

    function _getDomainSeperator(address contractAdress) private view returns (bytes32 separator) {
        bytes32 versionHash = keccak256(bytes("1"));
        bytes32 nameHash = keccak256(bytes("OrderManager"));

        assembly {
            let m := mload(0x40)
            mstore(m, _DOMAIN_TYPEHASH)
            mstore(add(m, 0x20), nameHash)
            mstore(add(m, 0x40), versionHash)
            mstore(add(m, 0x60), chainid())
            mstore(add(m, 0x80), contractAdress)
            separator := keccak256(m, 0xa0)
        }
    }

    function _getPermitHash(Order memory order, address contractAdress) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _getDomainSeperator(contractAdress),
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
