//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "./lib/PhotonFunctionSelectorLib.sol";

interface IProposer {

    /// @notice Propose a new operation to be executed in the destination chain (no matter execution order)
    /// @param protocolId The protocol ID of the operation
    /// @param destChainId The chain ID the operation is proposed for
    /// @param protocolAddress The protocol contract address in bytes format (abi.encoded address for EVM, and value size for non-EVM up to 128 bytes)
    /// @param functionSelector The function selector (encoded selector with PhotonFunctionSelectorLib)
    /// @param params The payload for the function call
    function propose(
        bytes32 protocolId,
        uint256 destChainId,
        bytes calldata protocolAddress,
        bytes calldata functionSelector,
        bytes calldata params
    ) external;

    /// @notice Propose a new ordered operation to be executed in the destination chain.
    /// This operation will be executed only after the previous one proposed from this chain was completed.
    /// @param protocolId The protocol ID of the operation
    /// @param destChainId The chain ID the operation is proposed for
    /// @param protocolAddress The protocol contract address in bytes format (abi.encoded address for EVM, and value size for non-EVM up to 128 bytes)
    /// @param functionSelector The function selector (encoded selector with PhotonFunctionSelectorLib)
    /// @param params The payload for the function call
    function proposeInOrder(
        bytes32 protocolId,
        uint256 destChainId,
        bytes calldata protocolAddress,
        bytes calldata functionSelector,
        bytes calldata params
    ) external;
}
