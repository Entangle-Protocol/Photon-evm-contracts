// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.19;

library PhotonFunctionSelectorLib {
    error PhotonFunctionSelectorLib__InvalidParams();
    uint constant SELECTOR_MAX_LEN = 32;
    /// @notice Selector types
    /// @param EVM EVM ABI selector, is abi.encode(bytes4(functionSelector))
    /// @param SOLANA_ANCHOR Solana anchor selector, is string with function name
    /// @param SOLANA_NATIVE Solana native selector, is zero bytes, just payload provided
    enum SelectorTypes {
        EVM,
        SOLANA_ANCHOR,
        SOLANA_NATIVE // selector is zero bytes
    }

    // /// @notice Function Selector struct
    // /// @param selectorType type of selector, if 0 - it's EVM ABI selector, else - something non-evm
    // /// @param selector encoded selector value, for EVM it's abi.encode(bytes4(functionSelector))
    // struct FunctionSelector {
    //     uint8 selectorType;
    //     bytes value;
    // }

    function encodeFunctionSelector(uint8 selectorType, bytes memory selector) internal pure returns (bytes memory encodedData) {
        if (selector.length > SELECTOR_MAX_LEN) revert PhotonFunctionSelectorLib__InvalidParams();
        uint8 selectorLength = uint8(selector.length);
        encodedData = new bytes(selectorLength + 2);

        assembly {
            // store 2 bytes of selectorType + selectorLength
            mstore8(add(encodedData, 32), selectorType)
            mstore8(add(encodedData, 33), selectorLength)

            // copy src array to dest data
            if gt(selectorLength, 0) {
                let src := add(selector, 32)
                let dest := add(encodedData, 34)
                // if selector is 32 bytes - mstore or 32 bytes
                if eq(selectorLength, 32) {
                    mstore(dest, mload(src))
                }
                // else - loop over each byte and copy
                if iszero(eq(selectorLength, 32)) {
                    for { let i := 0 } lt(i, selectorLength) { i := add(i, 1) } {
                        // load each byte one by one
                        mstore8(add(dest, i), and(shr(248, mload(add(src, i))), 0xFF))
                    }
                }
            }
        }
    }

    function decodeFunctionSelector(bytes memory encodedSelector) internal pure returns (uint8, bytes memory) {
        if (encodedSelector.length < 2 || encodedSelector.length > SELECTOR_MAX_LEN + 2) revert PhotonFunctionSelectorLib__InvalidParams();
        uint8 selectorType;
        uint selectorLength;
        assembly {
            // exctract first 2 bytes
            selectorType := and(shr(248, mload(add(encodedSelector, 32))), 0xFF)
            selectorLength := and(shr(248, mload(add(encodedSelector, 33))), 0xFF)
        }
        if (selectorLength + 2 != encodedSelector.length) revert PhotonFunctionSelectorLib__InvalidParams();
        bytes memory selectorValue = new bytes(selectorLength);
        assembly {
            if gt(selectorLength, 0) {
                let src := add(encodedSelector, 34)
                let dest := add(selectorValue, 32)
                // if selector is 32 bytes - mstore or 32 bytes
                if eq(selectorLength, 32) {
                    mstore(dest, mload(src))
                }
                // else - loop over each byte and copy
                if iszero(eq(selectorLength, 32)) {
                    for { let i := 0 } lt(i, selectorLength) { i := add(i, 1) } {
                        // load each byte one by one
                        mstore8(add(dest, i), and(shr(248, mload(add(src, i))), 0xFF))
                    }
                }
            }
        }
        return (selectorType, selectorValue);
    }

    function encodeEvmSelector(bytes4 functionSelector) internal pure returns (bytes memory) {
        return encodeFunctionSelector(0, abi.encode(functionSelector));
    }

}