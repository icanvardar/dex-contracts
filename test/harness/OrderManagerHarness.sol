// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { OrderManager } from "../../src/utils/OrderManager.sol";
import { ExecutionCall, ExecutionResult } from "../../src/types/Order.sol";

contract OrderManagerHarness is OrderManager {
    constructor(address _factory, uint8 chunkSize) OrderManager(_factory, chunkSize) { }

    function exposed_executeOrder(ExecutionCall memory executionCall) external returns (ExecutionResult memory) {
        return _executeOrder66(executionCall);
    }
}
