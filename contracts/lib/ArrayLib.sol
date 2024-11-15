// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.19;

/// @title A library for handling array operations
/// @notice This library defines structures for various governance messages that can be used in cross-protocol communications.
library ArrayLib {
    /// @notice Check if array of addresses contains given address
    /// @param arr - array
    /// @param x - element to find
    /// @param start - Start at index
    /// @param end - End at index
    function containsAddress(
        address[] memory arr,
        address x,
        uint start,
        uint end
    ) internal pure returns (bool) {
        for (uint i = start; i < end; ) {
            if (arr[i] == x) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Check if array of addresses contains given address
    /// @param arr - array
    /// @param x - element to find
    function containsAddress(address[] memory arr, address x) internal pure returns (bool) {
        return containsAddress(arr, x, 0, arr.length);
    }
}
