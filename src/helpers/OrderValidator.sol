// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { EIP712 } from "solady/utils/EIP712.sol";
import { Order, OrderLibrary } from "../types/Order.sol";
import { OrderTypedHash } from "../types/OrderTypedHash.sol";

abstract contract OrderValidator is EIP712 {
    using OrderLibrary for Order;

    /*//////////////////////////////////////////////////////////////////////////
                                  PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice order signatures history
    mapping(bytes signature => bool issued) internal signatures;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor() EIP712() { }

    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Check provided signature with given order
     * @param order given order related with signature
     * @param signature signature of given order
     */
    function validateSigner(Order memory order, bytes memory signature) internal view returns (bool) {
        return OrderTypedHash.wrap(_hashTypedData(order.hash())).validateOrderSigner(signature, order.from);
    }

    /**
     * @dev Required EIP712 internal function
     */
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "OrderManager";
        version = "1";
    }
}
