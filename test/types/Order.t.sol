// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { Token } from "../../src/types/Token.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { Order, OrderLibrary } from "../../src/types/Order.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract OrderTest is Test {
    using OrderLibrary for Order;

    address[] public path;
    uint256 public deadline;
    address public senderAddress;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    function setUp() public {
        senderAddress = makeAddr("sender");
        deadline = block.timestamp + 1;

        MockERC20 tokenA = new MockERC20("tokenA", "TA");
        MockERC20 tokenB = new MockERC20("tokenB", "TB");

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        path.push(address(token0));
        path.push(address(token1));
    }

    function test_ShouldBeSuccess_ValidateStructure() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.validateStructure(), true);
    }

    function test_ShouldBeSuccess_path_length_ValidateStructure() public {
        address[] memory pathIssue = new address[](3);

        Order memory order = Order(3e17, 1e17, pathIssue, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.validateStructure(), false);
    }

    function test_ShouldBeSuccess_orderFrom_zero_ValidateStructure() public {
        Order memory order = Order(3e17, 1e17, path, address(0), senderAddress, deadline, block.timestamp);

        assertEq(order.validateStructure(), false);
    }

    function test_ShouldBeSuccess_orderTo_zero_ValidateStructure() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, address(0), deadline, block.timestamp);

        assertEq(order.validateStructure(), false);
    }

    function test_ShouldBeSuccess_identicalAddresses_ValidateStructure() public {
        address[] memory pathIdenticialToken = new address[](2);
        pathIdenticialToken[0] = address(token0);
        pathIdenticialToken[1] = address(token0);

        Order memory order =
            Order(3e17, 1e17, pathIdenticialToken, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.validateStructure(), false);
    }

    function test_ShouldBeSuccess_insufficientInputAmount_ValidateStructure() public {
        Order memory order = Order(0, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.validateStructure(), false);
    }

    function test_ShouldBeSuccess_ValidateExpiration() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.validateExpiration(), true);
    }

    function test_ShouldBeSuccess_expire_ValidateExpiration() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline - 2, block.timestamp);

        assertEq(order.validateExpiration(), false);
    }

    function test_ShouldBeSuccess_SortTokens() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        (Token a, Token b) = order.sortTokens();

        (Token _currency0, Token _currency1) = sort(path[0], path[1]);

        assertEq(Token.unwrap(a), Token.unwrap(_currency0));
        assertEq(Token.unwrap(b), Token.unwrap(_currency1));
    }

    function test_ShouldBeSuccess_Hash() public {
        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        assertEq(order.hash(), _getPermitHash(order));
    }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       HELPERS
    //     ////////////////////////////////////////////////////////////////////////*/

    function _getPermitHash(Order memory order) private pure returns (bytes32) {
        return keccak256(
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
        );
    }

    function sort(address tokenA, address tokenB) private pure returns (Token _currency0, Token _currency1) {
        if (address(tokenA) < address(tokenB)) {
            (_currency0, _currency1) = (Token.wrap(address(tokenA)), Token.wrap(address(tokenB)));
        } else {
            (_currency0, _currency1) = (Token.wrap(address(tokenB)), Token.wrap(address(tokenA)));
        }
    }
}
