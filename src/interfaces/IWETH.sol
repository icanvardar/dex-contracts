// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

/**
 * @title IWETH
 * @dev Interface for the Wrapped Ether (WETH) contract.
 */
interface IWETH {
    /**
     * @dev Deposits Ether into the contract.
     */
    function deposit() external payable;

    /**
     * @dev Transfers Ether from the contract to the specified address.
     * @param to The address to transfer Ether to.
     * @param value The amount of Ether to transfer.
     * @return bool `true` if the transfer was successful, otherwise `false`.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Withdraws a specified amount of Ether from the contract.
     * @param value The amount of Ether to withdraw.
     */
    function withdraw(uint256 value) external;
}
