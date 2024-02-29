// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.21 <0.9.0;

import { PairFactory } from "../src/core/PairFactory.sol";
import { Router } from "../src/helpers/Router.sol";
import { OrderManager } from "../src/utils/OrderManager.sol";
import { MockERC20 } from "../test/mocks/MockERC20.sol";
import { WETH } from "vectorized/solady/tokens/WETH.sol";
import { RouterLib } from "./../src/libraries/RouterLib.sol";
import "forge-std/StdJson.sol";
import "forge-std/console.sol";

import { BaseScript } from "./Base.s.sol";

contract Deploy is BaseScript {
    struct AddressPayload {
        address feeToSetter;
        address weth;
    }

    uint8 public constant CHUNK_SIZE_LIMIT = 10;

    uint256 public deadline;

    WETH public weth;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    error UndefinedArgs();

    receive() external payable { }

    constructor() { }

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

    function run()
        public
        broadcast
        returns (PairFactory factory, Router router, OrderManager orderManager, address createdPairAddress)
    {
        AddressPayload memory addressPayload = readAddressesFromFile();
        address feeToSetter = addressPayload.feeToSetter;
        deadline = block.timestamp + 1000;
        uint256 token0TransferAmount = 1_000_000e18;
        uint256 token1TransferAmount = 1_000_000e18;

        //address wethAddress = addressPayload.weth;
        // if (wethAddress == address(0) || feeToSetter == address(0)) {
        //     revert UndefinedArgs();
        // }

        weth = new WETH();

        weth.deposit{ value: 5e18 }();

        factory = new PairFactory(feeToSetter);
        router = new Router(address(factory), address(weth));
        orderManager = new OrderManager(address(factory), CHUNK_SIZE_LIMIT);

        orderManager.addExecutor(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);

        string memory deployMode = vm.envString("DEPLOY_MODE");

        if (keccak256(abi.encodePacked(deployMode)) == keccak256(abi.encodePacked(("test")))) {
            console.log(
                "/* ////////////////////////////////////////////////////////// */\n",
                "/*                  Running Test Deploy Mode                  */\n",
                "/* ////////////////////////////////////////////////////////// */\n"
            );

            tokenA = new MockERC20("tokenA", "TA");
            tokenB = new MockERC20("tokenB", "TB");

            _addLiquidity(router, token0TransferAmount, token1TransferAmount);

            createdPairAddress = RouterLib.pairFor(address(factory), address(tokenA), address(tokenB));
        }
    }

    function _addLiquidity(
        Router _router,
        uint256 _tokenAAmount,
        uint256 _tokenBAmount
    )
        private
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        tokenA.approve(address(_router), _tokenAAmount);
        tokenB.approve(address(_router), _tokenBAmount);
        (amountA, amountB, liquidity) = _router.addLiquidity(
            address(tokenA),
            address(tokenB),
            _tokenAAmount,
            _tokenBAmount,
            _tokenAAmount,
            _tokenBAmount,
            0x70997970C51812dc3A010C7d01b50e0d17dc79C8,
            deadline
        );
    }
}
