// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/**
 * @title IFactory
 * @dev Interface for a factory contract managing UniswapV2 pairs.
 */
interface IFactory {
    /**
     * @dev Returns the address that receives the fee for UniswapV2 swaps.
     */
    function feeTo() external view returns (address);

    /**
     * @dev Returns the address allowed to set the fee for UniswapV2 swaps.
     */
    function feeToSetter() external view returns (address);

    /**
     * @dev Returns the address of the pair for two specified tokens, or 0 if none exists.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @return pair Address of the pair contract.
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /**
     * @dev Returns the address of the pair by index.
     * @param index Index of the pair.
     * @return pair Address of the pair contract.
     */
    function allPairs(uint256 index) external view returns (address pair);

    /**
     * @dev Returns the number of pairs created by this factory.
     */
    function allPairsLength() external view returns (uint256);

    /**
     * @dev Creates a new pair for the specified tokens and returns its address.
     * @param tokenA Address of the first token.
     * @param tokenB Address of the second token.
     * @return pair Address of the newly created pair contract.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /**
     * @dev Sets the address that receives the fee for UniswapV2 swaps.
     * @param _feeTo Address to receive the fee.
     */
    function setFeeTo(address _feeTo) external;

    /**
     * @dev Sets the address allowed to set the fee for UniswapV2 swaps.
     * @param _feeToSetter Address allowed to set the fee.
     */
    function setFeeToSetter(address _feeToSetter) external;
}
