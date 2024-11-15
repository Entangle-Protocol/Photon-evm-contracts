// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "../IProposer.sol";

import "hardhat/console.sol";

contract OneFunc {
    uint256 public Number;

    uint256 public lastSrcChainId;
    uint256 public lastSrcBlockNumber;
    bytes32[2] public lastSrcOpTxId;
    bytes32 public protocolId;
    IProposer public proposer;

    constructor(bytes32 _protocolId, IProposer _proposer) {
        protocolId = _protocolId;
        proposer = _proposer;
    }

    /// @param data encoded: (bytes32 protocolId, uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params)
    function increment(bytes memory data) external {
        (bytes32 _protocolId, uint256 _srcChainId, uint256 _srcBlockNumber, bytes32[2] memory _srcOpTxId, bytes memory _params) = abi.decode(data, (bytes32, uint256, uint256, bytes32[2], bytes));
        lastSrcChainId = _srcChainId;
        lastSrcBlockNumber = _srcBlockNumber;
        lastSrcOpTxId = _srcOpTxId;
        uint256 _inc = abi.decode(_params, (uint256));
        Number += _inc;
    }

    function proposeIncrement() external {
        proposer.propose(
            protocolId,
            block.chainid,
            abi.encode(address(this)),
            PhotonFunctionSelectorLib.encodeEvmSelector(bytes4(keccak256("increment(bytes)"))),
            abi.encode(1)
        );
    }

    function getNumber(bytes calldata b) external returns (uint256) {
        (,,,,bytes memory params) = abi.decode(b, (bytes32, uint256, uint256, bytes32[2], bytes));
        return Number;
    }

    function proposeGetNumber() external {
        proposer.propose(
            protocolId,
            block.chainid,
            abi.encode(address(this)),
            PhotonFunctionSelectorLib.encodeEvmSelector(bytes4(keccak256("getNumber(bytes)"))),
            abi.encode(0)
        );
    }
}
