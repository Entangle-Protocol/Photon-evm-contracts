// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.19;

/// @title A library for managing Photon operation meta data
/// @notice This library defines functions for managing Photon operation meta
/// @dev The current meta shema: [30 bytes<RESERVED>][1 byte<ordered>][1 byte<version>]
library PhotonOperationMetaLib {
    function setVersion(uint256 meta, uint8 version) internal pure returns(uint256) {
        return meta & ~uint256(0xff) | uint256(version);
    }
    function setInOrder(uint256 meta, bool ordered) internal pure returns(uint256) {
        meta = meta & ~uint256(0xff << 8);
        uint256 o = (ordered ? 1 : 0);
        return meta | (o << 8);
    }
    function getVersion(uint256 meta) internal pure returns(uint8) {
        return uint8(meta & 0xff);
    }
    function isInOrder(uint256 meta) internal pure returns(bool) {
        return (meta & (0xff << 8)) != 0;
    }
}