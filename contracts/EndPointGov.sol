//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

import "./EndPoint.sol";
import "./lib/GovMessagesLib.sol";
import "./lib/OperationLib.sol";

/// @title EndPointGov
/// @notice Contract for managing of protocols parameters on EndPoint
contract EndPointGov is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    OwnableUpgradeable
{
    error EndPointGov__EndPointAlreadySet();

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant ENDPOINT = keccak256("ENDPOINT");

    EndPoint public endPoint;

    function __chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    function initialize(address[1] calldata initAddr) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /*** ADMIN FUNCTIONS ***/
    function setSpotter(address _endpoint) external onlyRole(ADMIN) {
        if (address(endPoint) != address(0)) {
            revert EndPointGov__EndPointAlreadySet();
        }
        endPoint = EndPoint(_endpoint);
        _grantRole(ENDPOINT, _endpoint);
    }

    /*** LOGIC FUNTIONS ***/

    /// @notice add allowed protocol
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function addAllowedProtocol(bytes memory data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddAllowedProtocolMsg memory message = abi.decode(
            params,
            (GovMessages.AddAllowedProtocolMsg)
        );
        endPoint.addAllowedProtocol(
            message.protocolId,
            message.consensusTargetRate,
            message.transmitters
        );
    }

    /// @notice add allowed protocol address to aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function addAllowedProtocolAddress(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddAOrRemoveActorAddressMsg memory message = abi.decode(
            params,
            (GovMessages.AddAOrRemoveActorAddressMsg)
        );
        address protocolAddressDecoded = abi.decode(message.actorAddress, (address));
        endPoint.addAllowedProtocolAddress(message.protocolId, protocolAddressDecoded);
    }

    /// @notice remove allowed protocol address from aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function removeAllowedProtocolAddress(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddAOrRemoveActorAddressMsg memory message = abi.decode(
            params,
            (GovMessages.AddAOrRemoveActorAddressMsg)
        );
        address protocolAddressDecoded = abi.decode(message.actorAddress, (address));
        endPoint.removeAllowedProtocolAddress(message.protocolId, protocolAddressDecoded);
    }

    /// @notice add allowed protocol proposer contract address
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function addAllowedProposerAddress(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddAOrRemoveActorAddressMsg memory message = abi.decode(
            params,
            (GovMessages.AddAOrRemoveActorAddressMsg)
        );
        address protocolProposerAddressDecoded = abi.decode(message.actorAddress, (address));
        endPoint.addAllowedProposerAddress(message.protocolId, protocolProposerAddressDecoded);
    }

    /// @notice remove allowed protocol proposer contract address
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function removeAllowedProposerAddress(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddAOrRemoveActorAddressMsg memory message = abi.decode(
            params,
            (GovMessages.AddAOrRemoveActorAddressMsg)
        );
        address protocolProposerAddressDecoded = abi.decode(message.actorAddress, (address));
        endPoint.removeAllowedProposer(message.protocolId, protocolProposerAddressDecoded);
    }

    /// @notice add allowed executor for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function addExecutor(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddOrRemoveExecutorMsg memory message = abi.decode(
            params,
            (GovMessages.AddOrRemoveExecutorMsg)
        );
        address executorDecoded = abi.decode(message.executor, (address));
        endPoint.addExecutor(message.protocolId, executorDecoded);
    }

    /// @notice remove allowed executor for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32 srcOpTxId[2], bytes params
    function removeExecutor(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddOrRemoveExecutorMsg memory message = abi.decode(
            params,
            (GovMessages.AddOrRemoveExecutorMsg)
        );
        address executorDecoded = abi.decode(message.executor, (address));
        endPoint.removeExecutor(message.protocolId, executorDecoded);
    }

    /// @notice add allowed transmitter for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32 srcOpTxId[2], bytes params
    function addTransmitters(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddOrRemoveTransmittersMsg memory message = abi.decode(
            params,
            (GovMessages.AddOrRemoveTransmittersMsg)
        );
        endPoint.addTransmitters(message.protocolId, message.transmitters);
    }

    /// @notice remove allowed transmitter for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function removeTransmitters(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.AddOrRemoveTransmittersMsg memory message = abi.decode(
            params,
            (GovMessages.AddOrRemoveTransmittersMsg)
        );
        endPoint.removeTransmitters(message.protocolId, message.transmitters);
    }

    /// @notice update allowed transmitteres for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function updateTransmitters(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.UpdateTransmittersMsg memory message = abi.decode(
            params,
            (GovMessages.UpdateTransmittersMsg)
        );
        endPoint.addTransmitters(message.protocolId, message.toAdd);
        endPoint.removeTransmitters(message.protocolId, message.toRemove);
    }

    /// @notice set consensus target rate for specified protocol on aggregation spotter
    /// @param data encoded: uint256 srcChainId, uint256 srcBlockNumber, bytes32[2] srcOpTxId, bytes params
    function setConsensusTargetRate(bytes calldata data) external onlyRole(ENDPOINT) {
        (, , , , bytes memory params) = abi.decode(
            data,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        GovMessages.SetConsensusTargetRateMsg memory message = abi.decode(
            params,
            (GovMessages.SetConsensusTargetRateMsg)
        );
        endPoint.setConsensusTargetRate(message.protocolId, message.consensusTargetRate);
    }
}
