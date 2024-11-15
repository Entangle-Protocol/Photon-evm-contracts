//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./EndPoint.sol";
import "./MasterSmartContract.sol";
import "./lib/GovMessagesLib.sol";
import "./lib/PhotonFunctionSelectorLib.sol";

contract MSCProposeHelper is Initializable, UUPSUpgradeable, AccessControlUpgradeable {

    error MSCProposeHelper__CallerIsNotMasterSmartContract();

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant govProtocolId = bytes32("photon-gov");

    MasterSmartContract masterSmartContract;
    EndPoint endPoint;

    mapping(uint256 => bytes) public govContractAddresses;

    /*** END OF VARS ***/

    /// @notice Initialize
    /// @param initAddr[0] - admin
    /// @param initAddr[1] - MasterSmartContract address
    /// @param initAddr[2] - EndPoint address
    function initialize(address[3] calldata initAddr) external initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        masterSmartContract = MasterSmartContract(initAddr[1]);
        endPoint = EndPoint(initAddr[2]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    modifier onlyMsc() {
        if (_msgSender() != address(masterSmartContract)) {
            revert MSCProposeHelper__CallerIsNotMasterSmartContract();
        }
        _;
    }

    /*** SET FUNCTIONS ***/

    /// @notice Set gov contract address for specified chain
    /// @param _chainId chain id
    /// @param _govContractAddress endpont gov contract address
    function setGovContractAddress(uint256 _chainId, bytes calldata _govContractAddress) external onlyMsc {
        govContractAddresses[_chainId] = _govContractAddress;
    }

    /*** PROPOSAL FUNCTIONS ***/

    /// @notice Make proposal to adding allowed protocol to endPoint on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param consensusTargetRate consensus target rate
    /// @param transmitters protocol transmitters
    function proposeAddAllowedProtocol(
        bytes32 protocolId,
        uint256 chainId,
        uint256 consensusTargetRate,
        address[] memory transmitters
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x45a004b9
        ); // EndPointGov.addAllowedProtocol(bytes)
        GovMessages.AddAllowedProtocolMsg memory message = GovMessages.AddAllowedProtocolMsg(
            protocolId,
            consensusTargetRate,
            transmitters
        );
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to adding allowed protocol contract address to endPoint on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param protocolAddress protocol contract address on specified chain for adding
    function proposeAddAllowedProtocolAddress(
        bytes32 protocolId,
        uint256 chainId,
        bytes memory protocolAddress
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0xd296a0ff
        ); // EndPointGov.addAllowedProtocolAddress(bytes)
        GovMessages.AddAOrRemoveActorAddressMsg memory message = GovMessages
            .AddAOrRemoveActorAddressMsg(protocolId, protocolAddress);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to removing allowed protocol contract address from endPoint on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param protocolAddress protocol contract address on specified chain for removing
    function proposeRemoveAllowedProtocolAddress(
        bytes32 protocolId,
        uint256 chainId,
        bytes memory protocolAddress
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0xb0a4ca98
        ); // EndPointGov.removeAllowedProtocolAddress(bytes)
        GovMessages.AddAOrRemoveActorAddressMsg memory message = GovMessages
            .AddAOrRemoveActorAddressMsg(protocolId, protocolAddress);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to adding allowed proposer on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param proposerAddress proposer address on specified chain for adding
    function proposeAddAllowedProposerAddress(
        bytes32 protocolId,
        uint256 chainId,
        bytes memory proposerAddress
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0xce0940a5
        ); // EndPointGov.addAllowedProposerAddress(bytes)
        GovMessages.AddAOrRemoveActorAddressMsg memory message = GovMessages
            .AddAOrRemoveActorAddressMsg(protocolId, proposerAddress);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to removing allowed proposer on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param proposerAddress proposer address on specified chain for removing
    function proposeRemoveAllowedProposerAddress(
        bytes32 protocolId,
        uint256 chainId,
        bytes memory proposerAddress
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0xb8e5f3f4
        ); // EndPointGov.removeAllowedProposerAddress(bytes)
        GovMessages.AddAOrRemoveActorAddressMsg memory message = GovMessages
            .AddAOrRemoveActorAddressMsg(protocolId, proposerAddress);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to adding allowed executor to specified protocol on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param executor executor address or pubkey
    function proposeAddExecutor(
        bytes32 protocolId,
        uint256 chainId,
        bytes calldata executor
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0xe0aafb68
        ); // EndPointGov.addExecutor(bytes)
        GovMessages.AddOrRemoveExecutorMsg memory message = GovMessages.AddOrRemoveExecutorMsg(
            protocolId,
            executor
        );
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to removing allowed executor to specified protocol on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param executor executor address or pubkey
    function proposeRemoveExecutor(
        bytes32 protocolId,
        uint256 chainId,
        bytes calldata executor
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x04fa384a
        ); // EndPointGov.removeExecutor(bytes)
        GovMessages.AddOrRemoveExecutorMsg memory message = GovMessages.AddOrRemoveExecutorMsg(
            protocolId,
            executor
        );
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to adding allowed transmitter to specified protocol on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param transmitters transmitters array of evm address to add
    function proposeAddTransmitters(
        bytes32 protocolId,
        uint256 chainId,
        address[] memory transmitters
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x6c5f5666
        ); // EndPointGov.addTransmitters(bytes)
        GovMessages.AddOrRemoveTransmittersMsg memory message = GovMessages
            .AddOrRemoveTransmittersMsg(protocolId, transmitters);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to removing allowed transmitter to specified protocol on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param transmitters transmitter array of evm address to remove
    function proposeRemoveTransmitters(
        bytes32 protocolId,
        uint256 chainId,
        address[] memory transmitters
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x5206da70
        ); // EndPointGov.removeTransmitters(bytes)
        GovMessages.AddOrRemoveTransmittersMsg memory message = GovMessages
            .AddOrRemoveTransmittersMsg(protocolId, transmitters);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to update allowed transmitter to specified protocol on specified chain
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param toAdd transmitter array of evm addresses to add
    /// @param toRemove transmitter array of evm addresses to remove
    function proposeUpdateTransmitters(
        bytes32 protocolId,
        uint256 chainId,
        address[] memory toAdd,
        address[] memory toRemove
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x654b46e1
        ); // EndPointGov.updateTransmitters(bytes)
        GovMessages.UpdateTransmittersMsg memory message = GovMessages.UpdateTransmittersMsg(
            protocolId,
            toAdd,
            toRemove
        );
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }

    /// @notice Make proposal to set consensus target rate
    /// @param protocolId protocol id
    /// @param chainId target chain id
    /// @param consensusTargetRate consensus target rate
    function proposeSetConsensusTargetRate(
        bytes32 protocolId,
        uint256 chainId,
        uint256 consensusTargetRate
    ) external onlyMsc {
        bytes memory selector = PhotonFunctionSelectorLib.encodeEvmSelector(
            0x970b6109
        ); // EndPointGov.setConsensusTargetRate(bytes)
        GovMessages.SetConsensusTargetRateMsg memory message = GovMessages
            .SetConsensusTargetRateMsg(protocolId, consensusTargetRate);
        bytes memory params = abi.encode(message);
        endPoint.propose(govProtocolId, chainId, govContractAddresses[chainId], selector, params);
    }
}