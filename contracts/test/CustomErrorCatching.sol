// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "hardhat/console.sol";

contract TargetContract {
    error MyCustomError(uint256, bytes, address, string); // 0xf0dce77a

    constructor() {}

    function fail() public {
        revert MyCustomError(42, "hello", msg.sender, "world");
    }
}

contract CustomErrorCatchingTest {
    TargetContract target;

    constructor() {
        target = new TargetContract();
    }

    function tryToCatchCustomError() external {
        (bool success, bytes memory res) = address(target).call(abi.encodeWithSignature("fail()"));
        require(!success, "Should fail");
        uint len;
        assembly {
            len := mload(res)
        }
        console.log("len %s", len);
        console.logBytes(res);
        bytes4 sig;
        bytes memory data;
        assembly {
            mstore(sig, and(mload(add(res, 32)), 0xffffffff))
            data := add(res, 4)
        }
        console.log("sig");
        console.logBytes4(sig);
        (uint256 code, bytes memory bb, address addr, string memory message) = abi.decode(data, (uint256, bytes, address, string));
        require(code == 42, "Code is not 42");
        require(keccak256(bb) == keccak256("hello"), "Data is not hello");
        require(addr == address(this), "Address is not this");
        require(keccak256(bytes(message)) == keccak256("world"), "Message is not world");

        console.log("code %s", code);
        console.log("bytes data: %s", string(bb));
        console.log("addr: %s", addr);
        console.log("message: %s", message);
    }
}