// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/math/Math.sol";

import { Pair } from "../../src/core/Pair.sol";
import { Order, OrderLibrary } from "../../src/types/Order.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";
import { OrderManager } from "./../../src/utils/OrderManager.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";
import { OrderValidatorHarness } from "../harness/OrderValidatorHarness.sol";

contract OrderValidatorTest is Test {
    bytes32 public constant _DOMAIN_TYPEHASH = 0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    uint256 public deadline;

    OrderValidatorHarness public orderValidatorHarness;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    constructor() { }

    function setUp() public {
        deadline = block.timestamp + 1;

        MockERC20 tokenA = new MockERC20("tokenA", "TA");
        MockERC20 tokenB = new MockERC20("tokenB", "TB");

        orderValidatorHarness = new OrderValidatorHarness();

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);
    }

    function test_ShouldBeSuccess_Initialize() public {
        (
            bytes1 fields,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = orderValidatorHarness.eip712Domain();

        (string memory contractName, string memory contractVersion) =
            orderValidatorHarness.exposed_domaninNameAndVersion();

        assertEq(fields, hex"0f");
        assertEq(name, contractName);
        assertEq(version, contractVersion);
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(orderValidatorHarness));
        assertEq(salt, bytes32(0));
        assertEq(extensions, extensions);
    }

    function test_ShouldBeSuccess_Signatures() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);
        bool result;

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderValidatorHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        result = orderValidatorHarness.exposed_signatures(signature);

        assertEq(result, false);
    }

    function test_ShouldBeSuccess_CheckOrderSignature() public {
        bytes memory signature;
        address senderAddress = vm.addr(1);
        bool result;

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        Order memory order = Order(3e17, 1e17, path, senderAddress, senderAddress, deadline, block.timestamp);

        bytes32 permitMeesageHash = _getPermitHash(order, address(orderValidatorHarness));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);
        signature = abi.encodePacked(r, s, v);

        result = orderValidatorHarness.exposed_validateSigner(order, signature);

        assertEq(result, true);
    }

    function test_ShouldBeSuccess_DomainNameAndVersion() public {
        (string memory name, string memory version) = orderValidatorHarness.exposed_domaninNameAndVersion();

        assertEq(name, "OrderManager");
        assertEq(version, "1");
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
