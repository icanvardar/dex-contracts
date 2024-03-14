// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Ownable } from "solady/auth/Ownable.sol";
import { OrderValidator } from "../helpers/OrderValidator.sol";
import { Order, OrderStatus, ExecutionCall, ExecutionResult, OrderLibrary } from "../types/Order.sol";
import { IPair } from "../interfaces/IPair.sol";
import { Token } from "../types/Token.sol";

/**
 * @title OrderManager
 * @dev Handles limit order swaps by using users' signature.
 */
contract OrderManager is OrderValidator, Ownable {
    using OrderLibrary for Order;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC CONSTANTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice factory address
    address public immutable FACTORY;
    /// @notice maximum size of orders array
    uint8 public immutable CHUNK_SIZE_LIMIT;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC STORAGES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice executors list
    mapping(address executorAddress => bool active) public executors;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice executed order information
    event OrderExecuted(
        uint256 amountIn, uint256 amountOutMin, address[] indexed path, address indexed from, address to
    );
    /// @notice emitted after executor address is added
    event ExecutorAdded(address executorAddress);
    /// @notice emitted after executor address is removed
    event ExecutorRemoved(address executorAddress);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice given payload exceed chunk size
    error ChunkSizeExceeded();
    /// @notice zero address not accepted
    error NoZeroAddress();
    /// @notice executor has been already set
    error ExecutorAlreadySet();
    /// @notice not find this executor address
    error NoExecutorAddress();
    /// @notice only executors accepted
    error OnlyExecutor();
    /// @notice empty orders
    error EmptyOrdersNotSupported();

    /*//////////////////////////////////////////////////////////////////////////
                                      MODIFIER
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Checks caller is executor or not
     */
    modifier isExecutor() {
        if (!executors[msg.sender]) {
            revert OnlyExecutor();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Constructor of contract
     * @param _factory address of factory contract
     * @param chunkSize max chunk size
     */
    constructor(address _factory, uint8 chunkSize) {
        _initializeOwner(msg.sender);

        FACTORY = _factory;
        CHUNK_SIZE_LIMIT = chunkSize;
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Execute provided orders
     * @param calls array of orders
     * @return results boolean array of order results
     */
    function batchExecuteOrder(ExecutionCall[] calldata calls) external isExecutor returns (ExecutionResult[] memory) {
        uint256 callsLength = calls.length;

        if (callsLength == 0) {
            revert EmptyOrdersNotSupported();
        }

        if (callsLength > CHUNK_SIZE_LIMIT) {
            revert ChunkSizeExceeded();
        }

        ExecutionResult[] memory results = new ExecutionResult[](callsLength);

        uint256 i;
        for (i; i < callsLength; i++) {
            results[i] = _executeOrder66(calls[i]);
        }

        return results;
    }

    /**
     * @dev Adds executor address
     * @param executorAddress Address of executor
     */
    function addExecutor(address executorAddress) external onlyOwner {
        if (executorAddress == address(0)) {
            revert NoZeroAddress();
        }

        if (executors[executorAddress]) {
            revert ExecutorAlreadySet();
        }

        executors[executorAddress] = true;

        emit ExecutorAdded(executorAddress);
    }

    /**
     * @dev Removes executor address
     * @param executorAddress Address of executor
     */
    function removeExecutor(address executorAddress) external onlyOwner {
        if (executorAddress == address(0)) {
            revert NoZeroAddress();
        }

        if (!executors[executorAddress]) {
            revert NoExecutorAddress();
        }

        executors[executorAddress] = false;

        emit ExecutorRemoved(executorAddress);
    }

    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function which is execute order
     * @param call swap limit order
     * @return executed result of is order executed
     */
    function _executeOrder66(ExecutionCall memory call) internal returns (ExecutionResult memory) {
        Order memory order = call.order;
        bytes memory signature = call.signature;

        if (signatures[signature]) {
            return ExecutionResult(false, OrderStatus.ALREADY_ISSUED);
        }

        if (!order.validateStructure()) {
            return ExecutionResult(false, OrderStatus.INVALID_STRUCTURE);
        }

        if (!validateSigner(order, signature)) {
            return ExecutionResult(false, OrderStatus.INVALID_SIGNATURE);
        }

        signatures[signature] = true;

        (Token token0, Token token1) = order.sortTokens();

        if (Token.unwrap(token0) == address(0)) {
            return ExecutionResult(false, OrderStatus.WRONG_TOKEN_ADDRESS);
        }

        if (!order.validateExpiration()) {
            return ExecutionResult(false, OrderStatus.EXPIRED);
        }

        address pairAddress = token0.computePairAddress(token1, FACTORY);

        (uint256 amountIn, uint256 amountOut) = token0.calculateAmounts(pairAddress, order.amountIn, order.path[0]);

        if (amountOut == 0) {
            return ExecutionResult(false, OrderStatus.INSUFFICIENT_LIQUIDITY);
        }

        if (amountOut < order.amountOutMin) {
            return ExecutionResult(false, OrderStatus.SLIPPAGE_TOO_HIGH);
        }

        if (!Token.wrap(order.path[0]).transferFrom(order.from, pairAddress, amountIn)) {
            return ExecutionResult(false, OrderStatus.TRANSFER_FAILED);
        }

        (uint256 amount0Out, uint256 amount1Out) =
            order.path[0] == Token.unwrap(token0) ? (uint256(0), amountOut) : (amountOut, uint256(0));

        try IPair(pairAddress).swap(amount0Out, amount1Out, order.to, new bytes(0)) {
            emit OrderExecuted(order.amountIn, order.amountOutMin, order.path, order.from, order.to);

            return ExecutionResult(true, OrderStatus.FILLED);
        } catch {
            return ExecutionResult(false, OrderStatus.EXECUTION_FAILED);
        }
    }
}
