// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.19;

import "./UnsafeCalldataBytesLib.sol";

/**
 * @dev This library provides methods to construct and verify Merkle Tree proofs efficiently.
 *
 */

library MerkleTree {
    function hash(bytes memory input) internal pure returns (bytes32) {
        return bytes32(keccak256(input));
    }

    function nodeHash(
        bytes32 childA,
        bytes32 childB
    ) internal pure returns (bytes32) {
        if (childA > childB) {
            (childA, childB) = (childB, childA);
        }

        bytes32 rv = hash(abi.encodePacked(childA, childB));
        return rv;
    }

    /// @notice QuickSort recursive implementation
    /// @dev Taken from https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f
    function quickSort(bytes32[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if(i==j) return;
        uint pivot = uint(arr[uint(left + (right - left) / 2)]);
        while (i <= j) {
            while (uint(arr[uint(i)]) < pivot) i++;
            while (pivot < uint(arr[uint(j)])) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }

    function getLeftChildIdx(uint i) internal pure returns (uint) {
        return i * 2 + 1;
    }

    function getRightChildIdx(uint i) internal pure returns (uint) {
        return i * 2 + 2;
    }

    /// @notice Construct Merkle Tree from given list of hashes, which are used
    /// without further hashing
    /// @dev This function is only used for testing purposes and is not efficient
    function constructFromProofs(
        bytes32[] memory proofs
    ) internal pure returns (bytes32 root) {
        quickSort(proofs, 0, int(proofs.length - 1));
        bytes32[] memory tree = new bytes32[](2 * proofs.length - 1);

        // The tree is structured as follows:
        //    0
        //  1   2
        // 3 4 5 6
        // ...
        // In this structure:
        // * Parent of node x is (x-1) // 2,
        // * Children of node x are x*2 + 1 and x*2 + 2.
        // * Sibling of the node x is x - (-1)**(x % 2).
        // * The root is at index 0

        // Filling the leaf hashes
        for (uint i = 0; i < proofs.length; i++) {
            tree[tree.length - 1 - i] = proofs[i];
        }

        // Filling the node hashes from bottom to top
        for (uint i = tree.length - proofs.length; i > 0; i--) {
            tree[i-1] = nodeHash(tree[getLeftChildIdx(i-1)], tree[getRightChildIdx(i-1)]);
        }

        root = tree[0];
    }
}
