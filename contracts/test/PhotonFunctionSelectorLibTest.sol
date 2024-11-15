//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../lib/PhotonFunctionSelectorLib.sol";

import "hardhat/console.sol";

contract PhotonFunctionSelectorLibTest {

    constructor() {
    }

    function checkDecoded(uint8 srcType, bytes memory srcValue, uint8 destType, bytes memory destValue) internal pure {
        require(srcType == destType, "src selector type != dest selector type");
        require(srcValue.length == destValue.length, "src length != dest length");
        for (uint i; i < srcValue.length;) {
            require(srcValue[i] == destValue[i], "Is not equal!");
            unchecked { ++i; }
        }
    }

    function testFunctionSelectorPositive() public pure {
        console.log("Start encode evm selector");
        bytes4 evmSelector = bytes4(keccak256("transfer(address,uint256)"));
        bytes memory encoded = PhotonFunctionSelectorLib.encodeEvmSelector(evmSelector);
        console.logBytes(encoded);
        console.log("Start decode");
        (uint8 decodedType, bytes memory decodedValue) = PhotonFunctionSelectorLib.decodeFunctionSelector(encoded);
        console.log("Selector type: %s", decodedType);
        console.logBytes(decodedValue);

        checkDecoded(uint8(PhotonFunctionSelectorLib.SelectorTypes.EVM), abi.encode(evmSelector), decodedType, decodedValue);

        console.log("Start encode");
        encoded = PhotonFunctionSelectorLib.encodeFunctionSelector(uint8(PhotonFunctionSelectorLib.SelectorTypes.SOLANA_ANCHOR), "transfer_solana");
        console.logBytes(encoded);
        console.log("Start decode");
        (decodedType, decodedValue) = PhotonFunctionSelectorLib.decodeFunctionSelector(encoded);
                console.log("Selector type: %s", decodedType);
        console.logBytes(decodedValue);

        checkDecoded(uint8(PhotonFunctionSelectorLib.SelectorTypes.SOLANA_ANCHOR), "transfer_solana", decodedType, decodedValue);

        console.log("Start encode");
        encoded = PhotonFunctionSelectorLib.encodeFunctionSelector(uint8(PhotonFunctionSelectorLib.SelectorTypes.SOLANA_NATIVE), "");
        console.logBytes(encoded);
        console.log("Start decode");
        (decodedType, decodedValue) = PhotonFunctionSelectorLib.decodeFunctionSelector(encoded);
                console.log("Selector type: %s", decodedType);
        console.logBytes(decodedValue);

        checkDecoded(uint8(PhotonFunctionSelectorLib.SelectorTypes.SOLANA_NATIVE), "", decodedType, decodedValue);
    }

    function testFunctionSelectorNegative() public {
        bytes memory encoded = PhotonFunctionSelectorLib.encodeFunctionSelector(255, "This is more than 32 length selector");
    }
}