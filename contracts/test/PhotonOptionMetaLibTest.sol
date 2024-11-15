//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../lib/PhotonOperationMetaLib.sol";

import "hardhat/console.sol";

contract PhotonOperationMetaLibTest {
    function testMetaLib() external {
        console.log("Test PhotonOperationMetaLib");
        uint meta = PhotonOperationMetaLib.setVersion(0, 255);
        console.log("Meta: %s", meta);
        meta = PhotonOperationMetaLib.setInOrder(meta, true);
        console.log("Meta: %s", meta);
        require(PhotonOperationMetaLib.getVersion(meta) == 255, "Version is not 255");
        require(PhotonOperationMetaLib.isInOrder(meta), "Must be in order");

        meta = PhotonOperationMetaLib.setVersion(meta, 127);
        console.log("Meta: %s", meta);
        meta = PhotonOperationMetaLib.setInOrder(meta, false);
        console.log("Meta: %s", meta);
        require(PhotonOperationMetaLib.getVersion(meta) == 127, "Version is not 127");
        require(!PhotonOperationMetaLib.isInOrder(meta), "Must not be in order");
    }
}