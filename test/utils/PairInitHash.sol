// SPDX-License-Identifier: MIT
pragma solidity >=0.8.21 <0.9.0;

import { Pair } from "../../src/core/Pair.sol";

library PairInitHash {
    event InitHash(bytes32 a);

    function getInitHash() public returns (bytes memory bytecode) {
        bytecode = type(Pair).creationCode;

        emit InitHash(keccak256(abi.encodePacked(bytecode)));
    }
}
