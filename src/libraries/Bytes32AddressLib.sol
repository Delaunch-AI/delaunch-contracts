// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/// @title Bytes32AddressLib
/// @notice Library for converting between addresses and bytes32 values
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/utils/Bytes32AddressLib.sol)
library Bytes32AddressLib {
    /// @notice Convert the last 20 bytes of a bytes32 value to an address
    /// @param bytesValue The bytes32 value to convert
    /// @return The extracted address
    function fromLast20Bytes(
        bytes32 bytesValue
    ) internal pure returns (address) {
        return address(uint160(uint256(bytesValue)));
    }

    /// @notice Convert an address to bytes32 by filling the first 12 bytes with zeros
    /// @param addressValue The address to convert
    /// @return The padded bytes32 value
    function fillLast12Bytes(
        address addressValue
    ) internal pure returns (bytes32) {
        return bytes32(bytes20(addressValue));
    }
}
