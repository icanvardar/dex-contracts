// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { Token } from "./Token.sol";

/// @notice Enum representing various order statuses
enum OrderStatus {
    INVALID_SIGNATURE,
    SLIPPAGE_TOO_HIGH,
    EXECUTION_FAILED,
    EXPIRED,
    FILLED,
    INVALID_STRUCTURE,
    ALREADY_ISSUED,
    INSUFFICIENT_LIQUIDITY,
    WRONG_TOKEN_ADDRESS,
    TRANSFER_FAILED
}

/// @notice Struct containing information about a signed order
struct Order {
    uint256 amountIn; // Amount of input token
    uint256 amountOutMin; // Minimum amount of output token
    address[] path; // Path of tokens to swap
    address from; // Address of sender
    address to; // Address of recipient
    uint256 deadline; // Expiry deadline
    uint256 timestamp; // Creation timestamp
}

/// @notice Struct containing parameters for order execution
struct ExecutionCall {
    Order order; // Order to execute
    bytes signature; // Signature of the order
}

/// @notice Struct containing result of order execution
struct ExecutionResult {
    bool success; // Execution success status
    OrderStatus status; // Execution status
}

/**
 * @title Order Execution Library
 * @notice A library for managing the execution of signed orders
 */
library OrderLibrary {
    /**
     * @dev Type hash of the order struct
     */
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(" "uint256 amountIn," "uint256 amountOutMin," "address[] path," "address from," "address to,"
        "uint256 deadline," "uint256 timestamp" ")"
    );

    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Validates the structure of an order
     * @param order The order to be validated
     * @return Whether the order structure is valid or not
     */
    function validateStructure(Order memory order) internal pure returns (bool) {
        if (
            order.path.length != 2 || order.from == address(0) || order.to == address(0)
                || order.path[0] == order.path[1] || order.amountIn == 0
        ) {
            return false;
        }
        return true;
    }

    /**
     * @dev Validates the expiration of an order
     * @param order The order to be validated
     * @return Whether the order has expired or not
     */
    function validateExpiration(Order memory order) internal view returns (bool) {
        if (order.deadline < block.timestamp) {
            return false;
        }
        return true;
    }

    /**
     * @dev Sorts tokens in an order
     * @param order The order containing tokens to be sorted
     * @return tokenA The first token after sorting
     * @return tokenB The second token after sorting
     */
    function sortTokens(Order memory order) internal pure returns (Token, Token) {
        address tokenA = order.path[0];
        address tokenB = order.path[1];
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return (Token.wrap(token0), Token.wrap(token1));
    }

    /**
     * @dev Computes the hash of an order
     * @param order The order for which hash needs to be computed
     * @return hash The hash of the given order
     */
    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ORDER_TYPEHASH,
                order.amountIn,
                order.amountOutMin,
                keccak256(abi.encodePacked(order.path)),
                order.from,
                order.to,
                order.deadline,
                order.timestamp
            )
        );
    }
}
