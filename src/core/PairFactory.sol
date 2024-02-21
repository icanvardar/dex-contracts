// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { Pair } from "./Pair.sol";

/**
 * @title Factory
 * @dev The Factory contract manages the creation of Pair contracts, which represent trading pairs
 * in a decentralized exchange. It also provides functions to set fees and fee recipients.
 */
contract PairFactory {
    address public feeTo;
    address public feeToSetter;
    address[] public allPairs;

    mapping(address => mapping(address => address)) public getPair;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    error IdenticalAddresses();
    error ZeroAddress();
    error PairExists();
    error Forbidden();

    /**
     * @dev Constructor initializes the Factory contract with the provided feeToSetter address.
     * @param _feeToSetter The address allowed to set fee-related parameters.
     */
    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    /**
     * @dev Returns the length of allPairs array, representing the total number of created Pair contracts.
     * @return The length of allPairs array.
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @dev Creates a new Pair contract for the given token pair, adds it to allPairs, and emits an event.
     * @param tokenA The address of the first token in the pair.
     * @param tokenB The address of the second token in the pair.
     * @return pair The address of the created Pair contract.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) {
            revert IdenticalAddresses();
        }
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) {
            revert ZeroAddress();
        }
        if (getPair[token0][token1] != address(0)) {
            revert PairExists();
        }
        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = Create2.deploy(0, salt, bytecode);

        Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /**
     * @dev Sets the fee recipient address.
     * @param _feeTo The new fee recipient address.
     */
    function setFeeTo(address _feeTo) external {
        if (msg.sender != feeToSetter) {
            revert Forbidden();
        }
        feeTo = _feeTo;
    }

    /**
     * @dev Sets the feeToSetter address.
     * @param _feeToSetter The new feeToSetter address.
     */
    function setFeeToSetter(address _feeToSetter) external {
        if (msg.sender != feeToSetter) {
            revert Forbidden();
        }
        feeToSetter = _feeToSetter;
    }
}
