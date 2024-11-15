// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

interface IProcessingLib {
    function finalizeData(
        bytes32 key,
        bytes[] calldata data,
        address[] calldata voters
    ) external returns(bool success, bytes memory finalizedData, address[] memory rewardClaimers);
}
