// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

type OrderTypedHash is bytes32;

using OrderTypedHashLibrary for OrderTypedHash global;

library OrderTypedHashLibrary {
    /*//////////////////////////////////////////////////////////////////////////
                             INTERNAL CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Verifies the signer's address from a message digest `hash`, and the `signature`.
    function validateOrderSigner(
        OrderTypedHash hash,
        bytes memory signature,
        address signer
    )
        internal
        view
        returns (bool)
    {
        address recoveredAddress = address(1);

        /// @solidity memory-safe-assembly
        assembly {
            let m := mload(0x40) // Cache the free memory pointer.
            for { } 1 { } {
                mstore(0x00, hash)
                mstore(0x40, mload(add(signature, 0x20))) // `r`.
                if eq(mload(signature), 64) {
                    let vs := mload(add(signature, 0x40))
                    mstore(0x20, add(shr(255, vs), 27)) // `v`.
                    mstore(0x60, shr(1, shl(1, vs))) // `s`.
                    break
                }
                if eq(mload(signature), 65) {
                    mstore(0x20, byte(0, mload(add(signature, 0x60)))) // `v`.
                    mstore(0x60, mload(add(signature, 0x40))) // `s`.
                    break
                }
                recoveredAddress := 0
                break
            }
            recoveredAddress :=
                mload(
                    staticcall(
                        gas(), // Amount of gas left for the transaction.
                        recoveredAddress, // Address of `ecrecover`.
                        0x00, // Start of input.
                        0x80, // Size of input.
                        0x01, // Start of output.
                        0x20 // Size of output.
                    )
                )
            // `returndatasize()` will be `0x20` upon success, and `0x00` otherwise.
            if iszero(returndatasize()) { recoveredAddress := 0 }
            mstore(0x60, 0) // Restore the zero slot.
            mstore(0x40, m) // Restore the free memory pointer.
        }

        return (recoveredAddress == address(0) || recoveredAddress != signer) ? false : true;
    }
}
