// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.19;

/// @title A library for operation management in a multi-chain environment
/// @notice This library provides structures and functions to manage operations across different blockchains
library OperationLib {

    uint constant ADDRESS_MAX_LEN = 128;
    uint constant PARAMS_MAX_LEN = 4 * 1024;

    /// @dev Represents a digital signature
    struct Signature {
        uint8 v; // The recovery byte
        bytes32 r; // The first 32 bytes of the signature
        bytes32 s; // The second 32 bytes of the signature
    }

    /// @notice Structure for information that holds knowledge of the operation calling process
    /// @param protocolId The protocol ID of the operation
    /// @param meta mask for operation meta (see PhotonOperationOptionLib)
    /// @param srcChainId The chain ID where the operation was triggered for web3, and 0 for web2
    /// @param srcBlockNumber The block number where the operation was triggered for web3, and 0 for web2
    /// @param srcOpTxId The transaction ID which triggered this operation proposal (two 32 bytes words for Solana TX id)
    /// @param nonce A nonce to ensure uniqueness
    /// @param destChainId The chain ID the operation is proposed for
    /// @param protocolAddr The protocol contract address in bytes format (20 bytes address for EVM, and value size for non-EVM)
    /// @param functionSelector The function selector to execute (encoded packed FunctionSelector)
    /// @param params The parameters for the function call
    /// @param reserved Reserved for future use
    struct OperationData {
        bytes32 protocolId;
        uint256 meta;
        uint256 srcChainId;
        uint256 srcBlockNumber;
        bytes32[2] srcOpTxId;
        uint256 nonce;
        uint256 destChainId;
        bytes   protocolAddr;
        bytes   functionSelector;
        bytes   params;
        bytes   reserved;
    }
}
