// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";
import "forge-std/console.sol";

import { WETH } from "vectorized/solady/tokens/WETH.sol";
import { Ownable } from "vectorized/solady/auth/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

import { Pair } from "../../src/core/Pair.sol";
import { Router } from "../../src/helpers/Router.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { OrderManager } from "../../src/utils/OrderManager.sol";
import { ExecutionCall, ExecutionResult, Order, OrderStatus } from "../../src/types/Order.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { OrderManagerHarness } from "../harness/OrderManagerHarness.sol";

contract OrderManagerTest is Test {
    uint256 public constant TOKEN_A_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint256 public constant TOKEN_B_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint8 public constant CHUNK_SIZE_LIMIT = 2;
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 amountIn,uint256 amountOutMin,address[] path,address from,address to,uint256 deadline,uint256 timestamp)"
    );

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
    OrderManagerHarness public orderManagerHarness;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    event OrderExecuted(
        uint256 amountIn, uint256 amountOutMin, address[] indexed path, address indexed from, address to
    );

    event ExecutorAdded(address serviceAddress);
    event ExecutorRemoved(address serviceAddress);

    receive() external payable { }

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
        orderManagerHarness = new OrderManagerHarness(address(pairFactory), CHUNK_SIZE_LIMIT);

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

    function test_ShouldBeSuccess_harnessContract_Initialize() public {
        orderManagerHarness = new OrderManagerHarness(address(pairFactory), CHUNK_SIZE_LIMIT);

        assertEq(orderManagerHarness.FACTORY(), address(pairFactory));
        assertEq(orderManagerHarness.CHUNK_SIZE_LIMIT(), CHUNK_SIZE_LIMIT);
        assertEq(orderManagerHarness.owner(), address(this));
    }

    function test_ShouldBeSuccess_BatchExecuteOrder() public {
        uint256 WETHTransferAmount = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressZero = 5e18;
        uint256 senderAddressOne = 5e18;

        bytes[] memory signatures = new bytes[](2);
        address[][] memory paths = new address[][](2);
        address[] memory senderAddress = new address[](2);
        Order[] memory orders = new Order[](2);
        ExecutionCall[] memory orderCalls = new ExecutionCall[](2);

        senderAddress[0] = vm.addr(1);
        senderAddress[1] = vm.addr(2);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        paths[0] = new address[](2);
        paths[1] = new address[](2);

        paths[0][0] = address(token0);
        paths[0][1] = address(token1);

        paths[1][0] = address(token1);
        paths[1][1] = address(weth);

        orders[0] = Order(3e17, 1e17, paths[0], senderAddress[0], senderAddress[0], deadline, block.timestamp);
        orders[1] =
            Order(amount1Out, amount2Out, paths[1], senderAddress[1], senderAddress[1], deadline, block.timestamp);

        for (uint256 i; i < signatures.length; i++) {
            bytes32 permitMeesageHash = _getPermitHash(orders[i], address(orderManager));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(i + 1, permitMeesageHash);
            signatures[i] = abi.encodePacked(r, s, v);
        }

        for (uint256 i; i < signatures.length; i++) {
            orderCalls[i] = ExecutionCall(orders[i], signatures[i]);
        }

        token0.transfer(senderAddress[0], senderAddressZero);
        token1.transfer(senderAddress[1], senderAddressOne);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), WETHTransferAmount);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        vm.prank(senderAddress[0]);
        token0.approve(address(orderManager), 3e17);

        vm.prank(senderAddress[1]);
        token1.approve(address(orderManager), amount1Out);

        ExecutionResult[] memory results = new ExecutionResult[](orderCalls.length);

        vm.prank(web2Service);
        results = orderManager.batchExecuteOrder(orderCalls);

        for (uint256 i = 0; i < results.length; i++) {
            assertEq(results[i].success, true);
        }

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - senderAddressZero);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18 - senderAddressOne);

        assertEq(token0.balanceOf(senderAddress[0]), 5e18 - 3e17);
        assertEq(token1.balanceOf(senderAddress[0]), amount1Out);

        assertEq(token1.balanceOf(senderAddress[1]), 5e18 - amount1Out);
        assertEq(weth.balanceOf(senderAddress[1]), amount2Out);
    }

    function test_alreadyIssued_ExecuteOrder66() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 10e18;

        bytes memory signature;
        address senderAddress = vm.addr(1);
        ExecutionResult[] memory results = new ExecutionResult[](2);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        token0.transfer(senderAddress, senderAddressAmount);

        vm.prank(senderAddress);
        token0.approve(address(orderManagerHarness), 6e17);

        for (uint256 i = 0; i < results.length; i++) {
            results[i] = orderManagerHarness.exposed_executeOrder(orderCall);
        }

        bool signatureResult = orderManagerHarness.exposed_signatures(signature);

        assertEq(signatureResult, true);
        assertEq(results[0].success, true);
        assertEq(uint8(results[0].status), uint8(OrderStatus.FILLED));
        assertEq(results[1].success, false);
        assertEq(uint8(results[1].status), uint8(OrderStatus.ALREADY_ISSUED));
    }

    function test_validateStructure_path_length_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_STRUCTURE));
    }

    function test_validateStructure_orderFrom_zero_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, address(0), sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_STRUCTURE));
    }

    function test_validateStructure_orderTo_zero_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, address(0), deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_STRUCTURE));
    }

    function test_validateStructure_identicalAddresses_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token0);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_STRUCTURE));
    }

    function test_validateStructure_insufficientInputAmount_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(0, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_STRUCTURE));
    }

    //     signature valid geçiyor +
    //     signature recoverAddress issue +
    //     signature v değeri yokken geçiyor
    //     siganture v si farklı ise geçmiyor +
    //     signature r,s eksik ise geçmiyor +
    //     signature v aynı ama r,s değerini değişince geçmiyor +
    //     signature boş olabilir +

    function test_invalidSignature_recoverAddressIssue_ExecuteOrder66() public {
        bytes memory signature;

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, address(0x1), address(0x1), deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_SIGNATURE));
    }

    function test_invalidSignature_empty_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        signature = abi.encodePacked(bytes32(0), bytes32(0), uint8(0));

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_SIGNATURE));
    }

    function test_invalidSignature_v_issue_ExecuteOrder66() public {
        bytes memory signature;
        uint8 wrongV = 1;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, wrongV);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_SIGNATURE));
    }

    function test_invalidSignature_rs_notFound_ExecuteOrder66() public {
        bytes memory signature;
        address sender = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v,,) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INVALID_SIGNATURE));
    }

    function test_invalidSignature_rs_different_ExecuteOrder66() public {
        address sender = vm.addr(1);

        bytes[] memory signatures = new bytes[](2);
        ExecutionResult[] memory results = new ExecutionResult[](2);
        ExecutionCall[] memory orderCalls = new ExecutionCall[](2);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, sender, sender, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signatures[0] = abi.encodePacked(r, bytes32(0), v);
        signatures[1] = abi.encodePacked(bytes32(0), s, v);

        for (uint256 i; i < signatures.length; i++) {
            orderCalls[i] = ExecutionCall(order, signatures[i]);
        }

        for (uint256 i = 0; i < results.length; i++) {
            results[i] = orderManagerHarness.exposed_executeOrder(orderCalls[i]);
            assertEq(results[i].success, false);
            assertEq(uint8(results[i].status), uint8(OrderStatus.INVALID_SIGNATURE));
        }
    }

    // Bu signature ve order valid ama token address sıkıntı olabilir.

    function test_wrong_token_address0_ExecuteOrder() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.WRONG_TOKEN_ADDRESS));
    }

    function test_wrong_token_address1_ExecuteOrder() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(0);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.WRONG_TOKEN_ADDRESS));
    }

    // Dealine süresi geçmiş olabilir.

    function test_expired_ExecuteOrder() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline - 2, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.EXPIRED));
    }

    function test_insufficient_liquidity_ExecuteOrder() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.INSUFFICIENT_LIQUIDITY));
    }

    // Slippage to high

    function test_slippage_ExecuteOrder() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 10e18;

        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);

        Order memory order =
            Order(3e17, amount1Out + 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        token0.transfer(senderAddress, senderAddressAmount);

        vm.prank(senderAddress);
        token0.approve(address(orderManagerHarness), 3e17);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.SLIPPAGE_TOO_HIGH));
    }

    // Transfer fail check

    function test_transfer_fail_ExecuteOrder() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;
        uint256 senderAddressAmount = 10e18;

        bytes memory signature;
        address senderAddress = vm.addr(1);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderManagerHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        token0.transfer(senderAddress, senderAddressAmount);

        ExecutionCall memory orderCall = ExecutionCall(order, signature);

        ExecutionResult memory result = orderManagerHarness.exposed_executeOrder(orderCall);

        assertEq(result.success, false);
        assertEq(uint8(result.status), uint8(OrderStatus.TRANSFER_FAILED));
    }

    //     function test_executeOrder66_ExecuteOrder() public {
    //         uint256 token0TransferAmount = 1e18;
    //         uint256 token1TransferAmount = 1e18;
    //         uint256 senderAddressAmount = 10e18;

    //         bytes memory signature;
    //         address senderAddress = vm.addr(1);
    //         bool result;

    //         address[] memory path = new address[](2);
    //         path[0] = address(token0);
    //         path[1] = address(token1);

    //         OrderValidator.Order memory order =
    //             OrderValidator.Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

    //         bytes32 permitMeesageHash = _getPermitHash(order, address(orderValidatorHarness));

    //         (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
    //         signature = abi.encodePacked(r, s, v);

    //         token0.transfer(senderAddress, senderAddressAmount);

    //         _addLiquidity(token0TransferAmount, token1TransferAmount);

    //         vm.prank(senderAddress);
    //         token0.approve(address(orderValidatorHarness), 6e17);

    //         vm.expectEmit(true, true, true, true);
    //         emit OrderExecuted(order.amountIn, order.amountOutMin, order.path, order.from, order.to);
    //         result = orderValidatorHarness.exposed_executeOrder(order, signature);

    //         assertEq(result, true);
    //     }

    //     function test_CheckOrderSignature() public {
    //         bytes memory signature;
    //         address senderAddress = vm.addr(1);
    //         bool result;

    //         address[] memory path = new address[](2);
    //         path[0] = address(token0);
    //         path[1] = address(token1);

    //         OrderValidator.Order memory order =
    //             OrderValidator.Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

    //         bytes32 permitMeesageHash = _getPermitHash(order, address(orderValidatorHarness));

    //         (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
    //         signature = abi.encodePacked(r, s, v);

    //         result = orderValidatorHarness.exposed_checkOrderSignature(order, signature);

    //         assertEq(result, true);
    //     }

    //     function test_domainNameAndVersion() public {
    //         (string memory name, string memory version) = orderValidatorHarness.exposed_domainNameAndVersion();

    //         assertEq(name, "Order Validator");
    //         assertEq(version, "1");
    //     }

    //     function test_ShouldBeSuccess_AddExecutor() public {
    //         vm.expectEmit(true, false, false, false);
    //         emit ExecutorAdded(address(0x1));
    //         orderManager.addExecutor(address(0x1));

    //         assertEq(orderManager.executors(address(0x1)), true);
    //     }

    //     function test_ShouldBeSuccess_RemoveExecutor() public {
    //         vm.expectEmit(true, false, false, false);
    //         emit ExecutorRemoved(web2Service);
    //         orderManager.removeExecutor(web2Service);

    //         assertEq(orderManager.executors(web2Service), false);
    //     }

    //     function test_ShouldBeSuccess_SetOrderRouter() public {
    //         address prevRouter = orderManager.orderRouter();
    //         address newRouter = address(0x1);

    //         vm.expectEmit(true, false, false, false);
    //         emit SetOrderRouter(prevRouter, newRouter);
    //         orderManager.setOrderRouter(newRouter);

    //         assertEq(orderManager.orderRouter(), newRouter);
    //     }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       REVERTS
    //     ////////////////////////////////////////////////////////////////////////*/

    //     function test_Revert_emptyOrdersNotSupported_BatchExecuteOrder() public {
    //         ExecutionCall[] memory orderCalls = new ExecutionCall[](0);

    //         vm.prank(web2Service);
    //         vm.expectRevert(OrderManager.EmptyOrdersNotSupported.selector);
    //         orderManager.batchExecuteOrder(orderCalls);
    //     }

    //     function test_Revert_chunkSizeExceeded_BatchExecuteOrder() public {
    //         address senderAddress = vm.addr(1);
    //         bytes[] memory signatures = new bytes[](3);
    //         address[][] memory paths = new address[][](1);
    //         Order[] memory orders = new Order[](3);

    //         uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
    //         uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

    //         paths[0] = new address[](2);

    //         paths[0][0] = address(token0);
    //         paths[0][1] = address(token1);

    //         orders[0] = Order(3e17, 1e17, paths[0], senderAddress, senderAddress, deadline, block.timestamp);
    //         orders[1] = Order(amount1Out, amount2Out, paths[0], senderAddress, senderAddress, deadline,
    // block.timestamp);
    //         orders[2] = Order(amount1Out, amount2Out, paths[0], senderAddress, senderAddress, deadline,
    // block.timestamp);

    //         for (uint256 i; i < signatures.length; i++) {
    //             bytes32 permitMeesageHash = _getPermitHash(orders[i], address(orderManager));
    //             (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
    //             signatures[i] = abi.encodePacked(r, s, v);
    //         }

    //         ExecutionCall[] memory orderCalls = new ExecutionCall[](signatures.length);

    //         for (uint256 i; i < signatures.length; i++) {
    //             orderCalls[i] = ExecutionCall(orders[i], signatures[i]);
    //         }

    //         vm.prank(web2Service);
    //         vm.expectRevert(OrderManager.ChunkSizeExceeded.selector);
    //         orderManager.batchExecuteOrder(orderCalls);
    //     }

    //     function test_Revert_isExecutor_BatchExecuteOrder() public {
    //         ExecutionCall[] memory orders = new ExecutionCall[](1);

    //         vm.expectRevert(OrderManager.OnlyExecutor.selector);
    //         orderManager.batchExecuteOrder(orders);
    //     }

    //     function test_Revert_onlyOwner_AddExecutor() public {
    //         address caller = address(0x1);

    //         vm.prank(caller);
    //         vm.expectRevert(Ownable.Unauthorized.selector);
    //         orderManager.addExecutor(address(0x1));
    //     }

    //     function test_Revert_noZeroAddress_AddExecutor() public {
    //         vm.expectRevert(OrderManager.NoZeroAddress.selector);
    //         orderManager.addExecutor(address(0));
    //     }

    //     function test_Revert_executorAlreadySet_AddExecutor() public {
    //         vm.expectRevert(OrderManager.ExecutorAlreadySet.selector);
    //         orderManager.addExecutor(web2Service);
    //     }

    //     function test_Revert_onlyOwner_RemoveExecutor() public {
    //         address caller = address(0x1);

    //         vm.prank(caller);
    //         vm.expectRevert(Ownable.Unauthorized.selector);
    //         orderManager.removeExecutor(address(0x1));
    //     }

    //     function test_Revert_noZeroAddress_RemoveExecutor() public {
    //         vm.expectRevert(OrderManager.NoZeroAddress.selector);
    //         orderManager.removeExecutor(address(0));
    //     }

    //     function test_Revert_noExecutorAddress_RemoveExecutor() public {
    //         vm.expectRevert(OrderManager.NoExecutorAddress.selector);
    //         orderManager.removeExecutor(address(0x1));
    //     }

    //     function test_Revert_noZeroAddress_SetOrderRouter() public {
    //         vm.expectRevert(OrderManager.NoZeroAddress.selector);
    //         orderManager.setOrderRouter(address(0));
    //     }

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
                        ORDER_TYPEHASH,
                        order.amountIn,
                        order.amountOutMin,
                        order.path,
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
