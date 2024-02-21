// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Token } from "./Token.sol";

/// @notice Order statuses
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

/// @notice Signed order information
struct Order {
    uint256 amountIn;
    uint256 amountOutMin;
    address[] path;
    address from;
    address to;
    uint256 deadline;
    uint256 timestamp;
}

/// @notice Order execution function parameters
struct OrderCall {
    Order order;
    bytes signature;
}

/// @notice Order execution function result
struct OrderResult {
    bool success;
    OrderStatus status;
}

library OrderLibrary {
    /// @notice type hash of order struct
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 amountIn,uint256 amountOutMin,address[] path,address from,address to,uint256 deadline,uint256 timestamp)"
    );

    function validateStructure(Order memory order) internal pure returns (bool) {
        if (
            order.path.length != 2 || order.from == address(0) || order.to == address(0)
                || order.path[0] == order.path[1] || order.amountIn == 0
        ) {
            return false;
        }

        return true;
    }

    function validateExpiration(Order memory order) internal view returns (bool) {
        if (order.deadline < block.timestamp) {
            return false;
        }

        return true;
    }

    function sortTokens(Order memory order) internal pure returns (Token, Token) {
        address tokenA = order.path[0];
        address tokenB = order.path[1];

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        return (Token.wrap(token0), Token.wrap(token1));
    }

    function hash(Order memory order) internal pure returns (bytes32) {
        return keccak256(
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
        );
    }
}
