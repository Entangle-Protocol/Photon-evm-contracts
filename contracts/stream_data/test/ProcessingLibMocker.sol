//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

contract ProcessingLibMocker {
    constructor() { }

    struct FinalizationDataHistory {
        bytes32 key;
        bytes[] data;
        address[] voters;
    }

    FinalizationDataHistory[] public finalizationDataHistory;

    function finalizeData(
        bytes32 key,
        bytes[] calldata data,
        address[] calldata voters
    ) external returns(
            bool success,
            bytes memory finalizedData,
            address[] memory rewardClaimers
        )
    {
        finalizationDataHistory.push(FinalizationDataHistory(key, data, voters));
        success = true;
        finalizedData = data[0];
        rewardClaimers = voters;
        // return (true, bytes("0x"), voters);
    }
}
