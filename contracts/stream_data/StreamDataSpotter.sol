// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IProcessingLib.sol";
import "../MasterSmartContract.sol";
import "./StreamDataSpotterFactory.sol";
import "./MasterStreamDataSpotter.sol";
import "../staking/BetManager.sol";

contract StreamDataSpotter is AccessControl {
    event SetConsensusRate(uint256 newConsensusRate);
    event SetMinFinalizationInterval(uint256 newMinFinalizationInterval);

    error StreamDataSpotter__OnlyFactory();
    error StreamDataSpotter__OnlyAllowedKeys();
    error StreamDataSpotter__ProtocolIsNotRegistered(bytes32);
    error StreamDataSpotter__InvalidConsensusRate(uint);
    error StreamDataSpotter__NotEnoughTimeHasPassed(uint leftTime);
    error StreamDataSpotter__NotEnoughTransmittersHaveVoted(uint voted, uint neccessary);
    error StreamDataSpotter__AssetDoesNotExist(bytes32);
    error StreamDataSpotter__DataFinalizationFailed();
    error StreamDataSpotter__MasterStreamDataSpotterNotSet();

    bytes32 public constant ADMIN = keccak256("ADMIN");

    bytes32 public protocolId;
    bytes32 public sourceId;
    bool public onlyAllowedKeys;
    StreamDataSpotterFactory public immutable factory;
    IProcessingLib public immutable processingLib;
    MasterSmartContract public immutable masterSmartContract;

    /// @notice consensus rate for the spotter
    /// @dev The minimum rate of agents voted necessary for update to happen, in 2 decimals format (e.g. 10000 == 100%)
    uint256 public consensusRate;

    /// @notice minimum time between price finalization events
    uint256 public minFinalizationInterval;

    struct AgentVote {
        bytes value;
        uint256 timestamp;
    }

    mapping(bytes32 => mapping(address => AgentVote)) public votes;

    mapping(bytes32 dataKey => mapping(address transmitter => bool isVoted)) internal votedTransmitters;

    struct AssetInfo {
        /// @notice latest accepted value
        bytes acceptedValue;
        /// @notice hash of the current round
        uint256 currentRoundOpHash;
        /// @notice timestamp of last update
        uint256 updateTimestamp;
        /// @notice number of agents that voted since last update for that asset
        uint32 nVotes;
    }

    mapping(bytes32 => AssetInfo) public assetInfo;

    function __chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    function _onlyFactory() internal view {
        if (address(factory) != _msgSender()) {
            revert StreamDataSpotter__OnlyFactory();
        }
    }

    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    constructor(
        bytes32 _protocolId,
        bytes32 _sourceId,
        address _processingLib,
        address _masterSmartContract,
        uint256 _consensusRate,
        uint256 _minFinalizationInterval,
        bool _onlyAllowedKeys
    ) {
        // First, require that provided protocol is registered in MasterSmartContract
        masterSmartContract = MasterSmartContract(_masterSmartContract);
        bool isInit = masterSmartContract.isInitGlobal(_protocolId);
        if (!isInit) {
            revert StreamDataSpotter__ProtocolIsNotRegistered(_protocolId);
        }

        _grantRole(ADMIN, _msgSender());
        factory = StreamDataSpotterFactory(_msgSender());
        protocolId = _protocolId;
        sourceId = _sourceId;
        processingLib = IProcessingLib(_processingLib);
        consensusRate = _consensusRate;
        minFinalizationInterval = _minFinalizationInterval;
        onlyAllowedKeys = _onlyAllowedKeys;
    }

    /*
     * Factory (which is also AMDIN) functions
     */

    function setConsensusRate(uint256 newConsensusRate) external onlyRole(ADMIN) {
        // Require consensus rate to be > 50% and < 100%
        if (newConsensusRate <= 5000 || newConsensusRate > 10000) {
            revert StreamDataSpotter__InvalidConsensusRate(newConsensusRate);
        }
        consensusRate = newConsensusRate;
        emit SetConsensusRate(newConsensusRate);
    }

    function setMinFinalizationInterval(
        uint256 newMinFinalizationInterval
    ) external onlyRole(ADMIN) {
        minFinalizationInterval = newMinFinalizationInterval;
        emit SetMinFinalizationInterval(newMinFinalizationInterval);
    }

    /*
     * Agent functions
     */

    function proposeData(
        address transmitter,
        bytes32 dataKey,
        bytes calldata value
    ) external onlyFactory {
        AssetInfo storage asset = assetInfo[dataKey];

        // If this is the first vote for this asset, start new round
        if (asset.updateTimestamp == 0) {
            asset.updateTimestamp = block.timestamp;
            asset.currentRoundOpHash = getRoundOpHash(
                protocolId,
                sourceId,
                dataKey,
                asset.updateTimestamp
            );
        }

        bool isAgentVoted = votedTransmitters[dataKey][transmitter];

        // If this is the first vote since last round, place a bet on the new round
        if (!isAgentVoted) {
            votedTransmitters[dataKey][transmitter] = true;
            asset.nVotes++;

            factory.placeBet(
                protocolId,
                transmitter,
                BetManager.BetType.Data,
                asset.currentRoundOpHash
            );
        }

        // Check if consensus is ready to finalize
        // Get the number of allowed transmitters to calculate the percentage of voted transmitters
        uint256 numberOfAllowedTransmitters = masterSmartContract.numberOfAllowedTransmitters(
            protocolId
        );
        uint256 pVotedTransmitters = (asset.nVotes * 10000) / numberOfAllowedTransmitters;

        // If enough votes collected and enough time has passed since the last update,
        // declare consensus ready to finalize
        uint256 minUpdateTimestamp = asset.updateTimestamp + minFinalizationInterval;
        if ((pVotedTransmitters >= consensusRate) && (minUpdateTimestamp <= block.timestamp)) {
            MasterStreamDataSpotter masterSpotter = factory.masterStreamDataSpotter();
            masterSpotter.declareConsensusReadyToFinalize(protocolId, sourceId, dataKey);
        }

        votes[dataKey][transmitter] = AgentVote(value, block.timestamp);
    }

    /*
     * Executor functions
     */

    /// @notice Executor function that attempts to trigger update for a given dataKey asset
    function finalizeData(bytes32 dataKey) external onlyFactory {
        MasterStreamDataSpotter masterSpotter = factory.masterStreamDataSpotter();
        if (address(masterSpotter) == address(0)) {
            revert StreamDataSpotter__MasterStreamDataSpotterNotSet();
        }

        AssetInfo storage asset = assetInfo[dataKey];
        if (asset.updateTimestamp == 0) {
            revert StreamDataSpotter__AssetDoesNotExist(dataKey);
        }

        // Require that enough time has been past for finalization update
        uint256 latestUpdateTimestamp = assetInfo[dataKey].updateTimestamp;
        if (latestUpdateTimestamp + minFinalizationInterval > block.timestamp) {
            revert StreamDataSpotter__NotEnoughTimeHasPassed(
                latestUpdateTimestamp + minFinalizationInterval - block.timestamp
            );
        }

        // Require that enough transmitters have voted at this point
        uint256 numberOfAllowedTransmitters = masterSmartContract.numberOfAllowedTransmitters(
            protocolId
        );
        uint256 pVotedTransmitters = (asset.nVotes * 10000) / numberOfAllowedTransmitters;
        if (pVotedTransmitters < consensusRate) {
            revert StreamDataSpotter__NotEnoughTransmittersHaveVoted(
                asset.nVotes,
                (numberOfAllowedTransmitters * 10000) / consensusRate
            );
        }

        // Iterate over all agents to get their votes
        address[] memory agents = masterSmartContract.getTransmitters(protocolId);
        bytes[] memory agentVotes = new bytes[](agents.length);
        address[] memory votedAgents = new address[](agents.length);

        for (uint256 i = 0; i < agents.length; ) {
            address agent = agents[i];

            AgentVote memory agentVote = votes[dataKey][agent];
            votedAgents[i] = agent;
            agentVotes[i] = agentVote.value;

            unchecked {
                i++;
            }
        }

        // Finalize the data through processing lib
        (bool success, bytes memory finalizedData, address[] memory rewardClaimers) = processingLib
            .finalizeData(dataKey, agentVotes, votedAgents);
        if (!success) {
            revert StreamDataSpotter__DataFinalizationFailed();
        }

        asset.acceptedValue = finalizedData;
        asset.updateTimestamp = block.timestamp;
        asset.nVotes = 0;

        // Release voted transmitters for current round
        for (uint256 i = 0; i < agents.length; ) {
            address agent = agents[i];
            delete votedTransmitters[dataKey][agent];

            unchecked {
                i++;
            }
        }

        // Push finalized data to masterSpotter
        masterSpotter.pushFinalizedData(dataKey, FinalizedData(block.timestamp, finalizedData, dataKey));
        factory.releaseBetsAndReward(protocolId, rewardClaimers, asset.currentRoundOpHash);

        // Calculate OpHash for next round
        asset.currentRoundOpHash = getRoundOpHash(
            protocolId,
            sourceId,
            dataKey,
            asset.updateTimestamp
        );
    }

    /*
     * Unprivileged functions
     */

    /// @notice Function that calculates current round hash
    function getRoundOpHash(
        bytes32 _protocolId,
        bytes32 _sourceId,
        bytes32 _dataKey,
        uint256 startVotePeriod
    ) public pure returns (uint256) {
        return
            uint256(keccak256(abi.encodePacked(_protocolId, _sourceId, _dataKey, startVotePeriod)));
    }

    function getConsensusRate() external view returns (uint256) {
        return consensusRate;
    }

    function getLatestOpHash(bytes32 dataKey) external view returns (uint) {
        return getRoundOpHash(protocolId, sourceId, dataKey, assetInfo[dataKey].updateTimestamp);
    }
}
