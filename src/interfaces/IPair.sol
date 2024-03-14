// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

interface IPair {
    /**
     * @dev Returns the total supply of liquidity tokens.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Transfers tokens from one address to another.
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to transfer.
     * @return bool `true` if the transfer was successful, otherwise `false`.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Permits spending tokens on behalf of the owner using a signature.
     * @param owner The owner of the tokens.
     * @param spender The address allowed to spend the tokens.
     * @param value The amount of tokens allowed to be spent.
     * @param deadline The deadline by which the permit is valid.
     * @param v The recovery byte of the signature.
     * @param r The R component of the signature.
     * @param s The S component of the signature.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external;

    /**
     * @dev Returns the minimum amount of liquidity tokens.
     */
    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    /**
     * @dev Returns the address of the UniswapV2 factory contract.
     */
    function factory() external view returns (address);

    /**
     * @dev Returns the address of the first token in the pair.
     */
    function token0() external view returns (address);

    /**
     * @dev Returns the address of the second token in the pair.
     */
    function token1() external view returns (address);

    /**
     * @dev Returns the reserves of both tokens in the pair.
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @dev Returns the cumulative price of the first token in the pair.
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @dev Returns the cumulative price of the second token in the pair.
     */
    function price1CumulativeLast() external view returns (uint256);

    /**
     * @dev Returns the last value of K for the pair.
     */
    function kLast() external view returns (uint256);

    /**
     * @dev Mints liquidity tokens and assigns them to the specified address.
     * @param to The address to assign the minted liquidity tokens to.
     * @return liquidity The amount of liquidity tokens minted.
     */
    function mint(address to) external returns (uint256 liquidity);

    /**
     * @dev Burns liquidity tokens and returns the amount of tokens redeemed.
     * @param to The address to send the redeemed tokens to.
     * @return amount0 The amount of the first token redeemed.
     * @return amount1 The amount of the second token redeemed.
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /**
     * @dev Executes a swap between the tokens in the pair.
     * @param amount0Out The amount of the first token to receive.
     * @param amount1Out The amount of the second token to receive.
     * @param to The address to send the received tokens to.
     * @param data Additional data to be passed to the swap.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;

    /**
     * @dev Skims excess tokens from the pair and sends them to the specified address.
     * @param to The address to send the skimmed tokens to.
     */
    function skim(address to) external;

    /**
     * @dev Updates the reserves of the pair to the current values.
     */
    function sync() external;

    /**
     * @dev Initializes the pair with the specified tokens.
     * @param token0 Address of the first token.
     * @param token1 Address of the second token.
     */
    function initialize(address token0, address token1) external;
}
