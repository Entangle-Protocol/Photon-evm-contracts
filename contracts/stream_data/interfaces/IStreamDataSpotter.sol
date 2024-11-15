// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

interface IStreamDataSpotter {
    function finalizeData(bytes32 dataKey) external;
    function vote(bytes32 dataKey, bytes calldata value) external;
    function protocolId() external returns (bytes32);
    function sourceId() external returns (bytes32);
    function processingLib() external returns (address);
}
