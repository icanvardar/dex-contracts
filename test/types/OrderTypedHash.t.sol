// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { OrderTypedHash } from "../../src/types/OrderTypedHash.sol";
import { Order } from "../../src/types/Order.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract OrderTypedHashTest is Test {
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(uint256 amountIn,uint256 amountOutMin,address[] path,address from,address to,uint256 deadline,uint256 timestamp)"
    );

    address[] public path;
    uint256 public deadline;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    constructor() { }

    function setUp() public {
        deadline = block.timestamp + 1;

        MockERC20 tokenA = new MockERC20("tokenA", "TA");
        MockERC20 tokenB = new MockERC20("tokenB", "TB");

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        path.push(address(token0));
        path.push(address(token1));
    }

    function test_ShouldBeSuccess_ValidateOrderSigner() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);
        bytes32 permitMeesageHash = _getPermitHash(order, address(0x1));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        bool validSignatureContract =
            OrderTypedHash.wrap(_getPermitHash(order, address(0x1))).validateOrderSigner(signature, order.from);

        bool validSignature = _validateSignature(permitMeesageHash, v, r, s, senderAddress);

        assertEq(validSignatureContract, validSignature);
    }

    function test_ShouldBeSuccess_not_recoverAddress_ValidateOrderSigner() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        Order memory order = Order(3e17, 1e17, path, address(0x1), senderAddress, deadline, block.timestamp);
        bytes32 permitMeesageHash = _getPermitHash(order, address(0x1));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        bool validSignatureContract =
            OrderTypedHash.wrap(_getPermitHash(order, address(0x1))).validateOrderSigner(signature, order.from);

        bool validSignature = _validateSignature(permitMeesageHash, v, r, s, address(0x1));

        assertEq(validSignatureContract, validSignature);
    }

    function test_ShouldBeSuccess_zero_recoverAddress_ValidateOrderSigner() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);

        Order memory order = Order(3e17, 1e17, path, address(0), senderAddress, deadline, block.timestamp);
        bytes32 permitMeesageHash = _getPermitHash(order, address(0x1));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        bool validSignatureContract =
            OrderTypedHash.wrap(_getPermitHash(order, address(0x1))).validateOrderSigner(signature, order.from);

        bool validSignature = _validateSignature(permitMeesageHash, v, r, s, address(0));

        assertEq(validSignatureContract, validSignature);
    }

    //     /*//////////////////////////////////////////////////////////////////////////
    //                                       HELPERS
    //     ////////////////////////////////////////////////////////////////////////*/

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

    function _validateSignature(
        bytes32 typedHash,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address signer
    )
        private
        pure
        returns (bool)
    {
        address recoveredAddress = ecrecover(typedHash, v, r, s);
        return (recoveredAddress == address(0) || recoveredAddress != signer) ? false : true;
    }
}
