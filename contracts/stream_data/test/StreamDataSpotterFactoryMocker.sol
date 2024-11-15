// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../StreamDataSpotterFactory.sol";
import "../StreamDataSpotter.sol";

contract StreamDataSpotterFactoryMocker is StreamDataSpotterFactory {

    function debugAddSpotter(bytes32 protocolId, bytes32 sourceId, address spotter) external {
        isSpotter[spotter] = true;
        spottersMap[protocolId][sourceId] = StreamDataSpotter(spotter);
    }
}
