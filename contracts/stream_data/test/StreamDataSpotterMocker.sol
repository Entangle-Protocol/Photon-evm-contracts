// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../StreamDataSpotter.sol";

contract StreamDataSpotterMocker is StreamDataSpotter {
    constructor(
        bytes32 _protocolId,
        bytes32 _sourceId,
        address _processingLib,
        address _masterSmartContract,
        uint256 _consensusRate,
        uint256 _minFinalizationInterval,
        bool _onlyAllowedKeys
    ) StreamDataSpotter(
        _protocolId,
        _sourceId,
        _processingLib,
        _masterSmartContract,
        _consensusRate,
        _minFinalizationInterval,
        _onlyAllowedKeys
    ) { }
}
