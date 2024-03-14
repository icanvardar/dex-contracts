// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { console } from "forge-std/console.sol";
import { Test } from "forge-std/Test.sol";

import { PairInitHash } from "../utils/PairInitHash.sol";

contract PairInitHashTest is Test {
    function test_ShouldGetPairInitHash() public {
        console.logBytes32(keccak256(abi.encodePacked(PairInitHash.getInitHash())));
    }
}
