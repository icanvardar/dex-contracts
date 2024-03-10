// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { ERC20 } from "vectorized/solady/tokens/ERC20.sol";

/**
 * @title LPToken
 * @dev A simple ERC20 token representing Liquidity Pool (LP) tokens.
 */
contract LPToken is ERC20 {
    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the name of the token.
     * @return The name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return "Dex LP Token";
    }

    /**
     * @dev Returns the symbol of the token.
     * @return The symbol of the token.
     */
    function symbol() public view virtual override returns (string memory) {
        return "DLPT";
    }
}
