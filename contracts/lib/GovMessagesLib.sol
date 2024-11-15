// SPDX-License-Identifier: BSL1.1
pragma solidity ^0.8.19;

/// @title A library for handling governance messages across multiple protocols
/// @notice This library defines structures for various governance messages that can be used in cross-protocol communications.
library GovMessages {
    /// @notice Structure for setting a new DAO protocol owner
    /// @param protocolId Unique identifier for the protocol
    /// @param protocolOwner The new owner's address in bytes format
    struct SetDAOProtocolOwnerMsg {
        bytes32 protocolId;
        bytes protocolOwner;
    }

    /// @notice Message for initializing a new protocol at the destination aggregation spotter
    /// @param protocolId Unique identifier for the protocol
    /// @param consensusTargetRate The target rate for consensus, used in decision-making processes
    /// @param transmitters Array of addresses designated as transmitters for the protocol
    struct AddAllowedProtocolMsg {
        bytes32 protocolId;
        uint256 consensusTargetRate;
        address[] transmitters;
    }

    /// @notice Message for adding or removing an allowed protocol or proposer address
    /// @param protocolId Unique identifier for the protocol
    /// @param actorAddress The address of the protocol or proposer to be added or removed, in bytes format
    struct AddAOrRemoveActorAddressMsg {
        bytes32 protocolId;
        bytes actorAddress;
    }

    /// @notice Message for adding or removing an executor
    /// @param protocolId Unique identifier for the protocol
    /// @param executor The executor's address in bytes format
    struct AddOrRemoveExecutorMsg {
        bytes32 protocolId;
        bytes executor;
    }

    /// @notice Message for adding or removing transmitters
    /// @param protocolId Unique identifier for the protocol
    /// @param transmitters Array of transmitter addresses to be added or removed
    struct AddOrRemoveTransmittersMsg {
        bytes32 protocolId;
        address[] transmitters;
    }

    /// @notice Message for adding or removing transmitters
    /// @param protocolId Unique identifier for the protocol
    /// @param toAdd Array of transmitter addresses to be added
    /// @param toRemove Array of transmitter addresses to be removed
    struct UpdateTransmittersMsg {
        bytes32 protocolId;
        address[] toAdd;
        address[] toRemove;
    }

    /// @notice Message for setting the consensus target rate
    /// @param protocolId Unique identifier for the protocol
    /// @param consensusTargetRate New target rate for consensus, expressed with 10000 as the base for decimals
    struct SetConsensusTargetRateMsg {
        bytes32 protocolId;
        uint256 consensusTargetRate;
    }
}
