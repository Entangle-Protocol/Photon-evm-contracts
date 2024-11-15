// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./StreamDataSpotterFactory.sol";
import "./StreamDataSpotter.sol";
import "../lib/MerkleTree.sol";

struct FinalizedData {
    uint256 timestamp;
    bytes finalizedData;
    bytes32 dataKey;
}

contract MasterStreamDataSpotter is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{

    error MasterStreamDataSpotter__OnlyDataSpotter();
    error MasterStreamDataSpotter__OnlyDataSpotterFactory();
    error MasterStreamDataSpotter__DataKeyNotAllowed(bytes32);
    error MasterStreamDataSpotter__NotEnoughFinalizationsForMerkleRoot();

    // Event after each data finalization
    event DataFinalized(
        bytes32 indexed protocolId,
        bytes32 indexed sourceId,
        bytes32 indexed dataKey,
        uint256 timestamp,
        bytes data
    );

    // Event emitted after each merkle root recalculation
    event NewMerkleRoot(bytes32 indexed protocolId, bytes32 indexed sourceId, bytes32 newMerkleRoot);
    // Event to indicate that a StreamDataSpotter has declared consensus ready to finalize
    event ConsensusReadyToFinalize(bytes32 indexed protocolId, bytes32 indexed sourceId, bytes32 indexed dataKey);

    bytes32 public constant ADMIN = keccak256("ADMIN");

    StreamDataSpotterFactory public factory;

    /// @notice This type stores information related to the spotter's data. It includes details such as the allowed keys (if permission is necessary), the Merkle root, and the finalized data.
    struct SpotterData {
        // Allowed keys for this spotter
        bytes32[] allowedKeys;
        // Latest merkle root
        bytes32 merkleRoot;
        // Mapping of dataKey to the latest finalized data for that asset
        mapping(bytes32 => FinalizedData) finalizedData;
        // Snapshot for all allowed keys that was used to calculate the latest merkle root
        mapping(bytes32 => FinalizedData) latestSnapshot;
        // number of finalizations happened since last merkle root calculation,
        // Used to determine wheather the merkle root recalculation is needed
        uint256 finalizationsSinceLastMerkleRoot;
    }

    mapping(bytes32 protocolId => mapping(bytes32 sourceId => SpotterData)) public spotterData;

    /// @notice Initializer
    /// @param initAddr - 0: admin, 1: factory
    function initialize(address[2] calldata initAddr) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        factory = StreamDataSpotterFactory(initAddr[1]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    function _onlyDataSpotter() internal view {
        if (!factory.isSpotter(_msgSender())) {
            revert MasterStreamDataSpotter__OnlyDataSpotter();
        }
    }
    modifier onlyDataSpotter() {
        _onlyDataSpotter();
        _;
    }

    function _onlyDataSpotterFactory() internal view {
        if (address(factory) != _msgSender()) {
            revert MasterStreamDataSpotter__OnlyDataSpotterFactory();
        }
    }
    modifier onlyDataSpotterFactory() {
        _onlyDataSpotterFactory();
        _;
    }

    /*
     * Spotter functions
     */

    /// @notice factory function to set allowed keys for spotter
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param allowedKeys array of allowed dataKeys
    function setAllowedKeys(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32[] calldata allowedKeys
    ) external onlyDataSpotterFactory {
        spotterData[protocolId][sourceId].allowedKeys = allowedKeys;
    }

    function checkIsAllowedKey(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32 dataKey
    ) internal view returns (bool) {
        for (uint i = 0; i < spotterData[protocolId][sourceId].allowedKeys.length; i++) {
            if (spotterData[protocolId][sourceId].allowedKeys[i] == dataKey) {
                return true;
            }
        }
        return false;
    }

    /// @notice Build the merkle tree from provided proofs and return the root
    function calcMerkleRoot(bytes32[] memory merkleProofs) internal pure returns (bytes32) {
        return MerkleTree.constructFromProofs(merkleProofs);
    }

    /// @notice Function for spotters to push their finalized data to proceed with aggregation
    /// @param dataKey data key
    /// @param data finalized data
    function pushFinalizedData(
        bytes32 dataKey,
        FinalizedData memory data
    ) external onlyDataSpotter {
        StreamDataSpotter spotter = StreamDataSpotter(_msgSender());

        bytes32 protocolId = spotter.protocolId();
        bytes32 sourceId = spotter.sourceId();
        bool onlyAllowedKeys = spotter.onlyAllowedKeys();

        spotterData[protocolId][sourceId].finalizedData[dataKey] = data;

        // Check datakey for spotters with allowed keys
        if (onlyAllowedKeys) {
            if (!checkIsAllowedKey(protocolId, sourceId, dataKey)) {
                revert MasterStreamDataSpotter__DataKeyNotAllowed(dataKey);
            }
        }

        spotterData[protocolId][sourceId].finalizationsSinceLastMerkleRoot++;

        emit DataFinalized(protocolId, sourceId, dataKey, data.timestamp, data.finalizedData);
    }

    function recalculateMerkleRoot(bytes32 protocolId, bytes32 sourceId) external {
        // Revert if no finalizations happened since last merkle root calculation
        if (spotterData[protocolId][sourceId].finalizationsSinceLastMerkleRoot == 0) {
            revert MasterStreamDataSpotter__NotEnoughFinalizationsForMerkleRoot();
        }

        // Merkle tree is built from finalizedData for each dataKey of StreamDataSpotter.
        // For each dataKey, the finalizedData is encoded and hashed, and the hash is used as a leaf in the Merkle tree.
        bytes32[] memory merkleProofs = new bytes32[](spotterData[protocolId][sourceId].allowedKeys.length);
        for (uint i = 0; i < spotterData[protocolId][sourceId].allowedKeys.length; i++) {
            bytes32 key = spotterData[protocolId][sourceId].allowedKeys[i];

            bytes memory encodedBytes = abi.encode(
                spotterData[protocolId][sourceId].finalizedData[key].timestamp,
                spotterData[protocolId][sourceId].finalizedData[key].finalizedData,
                spotterData[protocolId][sourceId].finalizedData[key].dataKey
            );

            merkleProofs[i] = keccak256(bytes.concat(keccak256(encodedBytes)));

            // Save current finalized data to latest snapshot
            spotterData[protocolId][sourceId].latestSnapshot[key] = spotterData[protocolId][sourceId].finalizedData[key];
        }

        // Recalculate and save merkle root
        spotterData[protocolId][sourceId].merkleRoot = calcMerkleRoot(merkleProofs);
        // Reset finalizations counter, thus preventing from multiple merkle
        // root recalculations in the block
        spotterData[protocolId][sourceId].finalizationsSinceLastMerkleRoot = 0;

        // Emit event to signalize new MerkleRoot
        emit NewMerkleRoot(protocolId, sourceId, spotterData[protocolId][sourceId].merkleRoot);
    }

    /// @notice Function for spotters to declare consensus ready to finalize
    /// @dev called by any Stream Data Spotter contract
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKey data key
    function declareConsensusReadyToFinalize(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32 dataKey
    ) external onlyDataSpotter {
        emit ConsensusReadyToFinalize(protocolId, sourceId, dataKey);
    }


    /*
     * Getters
     */

    function getFinalizationsSinceLastMerkleRoot(bytes32 protocolId, bytes32 sourceId) external view returns (uint256) {
        return spotterData[protocolId][sourceId].finalizationsSinceLastMerkleRoot;
    }

    /// @notice get finalized data for specific sourceId and dataKey
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKey data key
    function getFinalizedData(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32 dataKey
    ) external view returns (FinalizedData memory) {
        return spotterData[protocolId][sourceId].finalizedData[dataKey];
    }

    /// @notice Get allowed keys list for specific protocolId and sourceId
    /// @param protocolId protocol id
    /// @param sourceId source id
    function getAllowedKeys(bytes32 protocolId, bytes32 sourceId) external view returns (bytes32[] memory) {
        return spotterData[protocolId][sourceId].allowedKeys;
    }

    /// @notice Get array of finalized values that were used for latest merkle root recalculation
    /// @param protocolId protocol id
    /// @param sourceId source id
    function getLatestSnapshotValues(bytes32 protocolId, bytes32 sourceId) external view returns (FinalizedData[] memory) {
        // Create return array
        FinalizedData[] memory latestSnapshotValues = new FinalizedData[](spotterData[protocolId][sourceId].allowedKeys.length);
        
        // For each allowed key, get the latest snapshot value
        for (uint i = 0; i < spotterData[protocolId][sourceId].allowedKeys.length; i++) {
            bytes32 dataKey = spotterData[protocolId][sourceId].allowedKeys[i];
            latestSnapshotValues[i] = spotterData[protocolId][sourceId].latestSnapshot[dataKey];
        }
        return latestSnapshotValues;
    }
}
