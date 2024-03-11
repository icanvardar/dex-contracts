// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { OrderValidator } from "../../src/helpers/OrderValidator.sol";
import { Order } from "../../src/types/Order.sol";

contract OrderValidatorHarness is OrderValidator {
    function exposed_signatures(bytes memory signature) external view returns (bool) {
        return signatures[signature];
    }

    function exposed_validateSigner(Order memory order, bytes memory signature) external view returns (bool) {
        return validateSigner(order, signature);
    }

    function exposed_domaninNameAndVersion() external pure returns (string memory name, string memory version) {
        return _domainNameAndVersion();
    }
}
