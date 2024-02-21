// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { PairFactory } from "../src/core/PairFactory.sol";
import { Router } from "../src/helpers/Router.sol";
import { OrderManager } from "../src/utils/OrderManager.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    struct AddressPayload {
        address feeToSetter;
        address weth;
    }

    error UndefinedArgs();

    function concatenateStringAndUint256(string memory str, uint256 num) public pure returns (string memory) {
        // Concatenate the two strings
        string memory result = string(abi.encodePacked(str, vm.toString(num)));

        return result;
    }

    function readAddressesFromFile() public view returns (AddressPayload memory addressPayload) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/data/addresses.json");
        string memory json = vm.readFile(path);
        // bytes memory addresses = stdJson.parseRaw(json, ".421614");
        bytes memory addresses = stdJson.parseRaw(json, concatenateStringAndUint256(".", block.chainid));
        addressPayload = abi.decode(addresses, (AddressPayload));
    }

    function run() public broadcast returns (PairFactory factory, Router router, OrderManager orderManager) {
        AddressPayload memory addressPayload = readAddressesFromFile();
        address wethAddress = addressPayload.weth;
        address feeToSetter = addressPayload.feeToSetter;
        uint8 CHUNK_SIZE_LIMIT = 10;

        if (wethAddress == address(0) || feeToSetter == address(0)) {
            revert UndefinedArgs();
        }

        factory = new PairFactory(feeToSetter);
        router = new Router(address(factory), wethAddress);
        orderManager = new OrderManager(address(factory), CHUNK_SIZE_LIMIT);
    }
}
