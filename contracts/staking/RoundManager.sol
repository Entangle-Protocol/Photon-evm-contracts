//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./ExternalDeveloperHub.sol";
import "./StakingManager.sol";
import "./AgentManager.sol";
import "../MasterSmartContract.sol";
import "../stream_data/StreamDataSpotterFactory.sol";
import "../lib/ArrayLib.sol";

contract RoundManager is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant ROUND_TRIGGER = keccak256("ROUND_TRIGGER");

    error RoundManager__MinRoundTimeNotReached();

    event NewRound(uint roundId);

    /// @notice setContracts init marker
    bool isInit;
    ExternalDeveloperHub externalDeveloperHub;
    StakingManager stakingManager;
    AgentManager agentManager;
    BetManager betManager;
    MasterSmartContract masterSmartContract;
    StreamDataSpotterFactory streamDataSpotterFactory;
    GlobalConfig globalConfig;

    /// @notice Timestamp of last turnRound call
    uint public lastRoundTimestamp;

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    /// @param initAddr[1] - Round trigger address
    function initialize(address[2] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        _setRoleAdmin(ROUND_TRIGGER, ADMIN);
        _grantRole(ROUND_TRIGGER, initAddr[1]);
    }

    /// @notice Set contracts addresses
    /// @param initAddr[0] - externalDeveloperHub
    /// @param initAddr[1] - stakingManager
    /// @param initAddr[2] - agentManager
    /// @param initAddr[3] - betManager
    /// @param initAddr[4] - masterSmartContract
    /// @param initAddr[5] - streamDataSpotterFactory
    /// @param initAddr[6] - globalConfig
    function setContracts(address[7] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        externalDeveloperHub = ExternalDeveloperHub(initAddr[0]);
        stakingManager = StakingManager(initAddr[1]);
        agentManager = AgentManager(initAddr[2]);
        betManager = BetManager(initAddr[3]);
        masterSmartContract = MasterSmartContract(initAddr[4]);
        streamDataSpotterFactory = StreamDataSpotterFactory(initAddr[5]);
        globalConfig = GlobalConfig(initAddr[6]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice Execute reward distribution for last round, elect agents for each protocol for new round, and reset reward counter
    function turnRound() external onlyRole(ROUND_TRIGGER) {
        if (block.timestamp - lastRoundTimestamp < globalConfig.minRoundTime()) {
            revert RoundManager__MinRoundTimeNotReached();
        }
        stakingManager.distributeRewards();
        externalDeveloperHub.turnRound();
        stakingManager.turnRound();
        bytes32[] memory protocols = externalDeveloperHub.getActiveProtocols();
        stakingManager.updateAgents(protocols);
        streamDataSpotterFactory.turnRound();
        lastRoundTimestamp = block.timestamp;

        emit NewRound(stakingManager.round());
    }
}
