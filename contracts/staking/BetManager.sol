//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./StakingManager.sol";
import "./AgentManager.sol";
import "./ExternalDeveloperHub.sol";
import "./GlobalConfig.sol";
import "../MasterSmartContract.sol";

contract BetManager is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    error BetManager__ProtocolIsPaused(bytes32);
    error BetManager__AgentNotFound(address);
    error BetManager__InvalidBetType(uint);
    error BetManager__InvalidOpHash(uint);
    error BetManager__TimeoutNotElapsed();
    error BetManager__TryingToDiscardZeroBet();

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant PRUNER = keccak256("PRUNER");
    bytes32 public constant BETTER = keccak256("BETTER");
    bytes32 public constant STAKING_MANAGER = keccak256("STAKING_MANAGER");

    struct AgentReward {
        address agent;
        uint amount;
    }

    enum BetType {
        Msg,
        Data
    }

    struct Bet {
        uint amount;
        uint timestamp;
    }

    struct AgentStatistic {
        uint bets;
        uint betsAmount;
        uint unlockedAmount;
        uint rewards;
        uint rewardsAmount;
    }

    StakingManager stakingManager;
    AgentManager agentManager;
    ExternalDeveloperHub externalDeveloperHub;
    MasterSmartContract masterSmartContract;
    GlobalConfig globalConfig;

    /// @notice setContracts init marker
    bool isInit;
    /// @notice Stores agent rewards for current round
    AgentReward[] public agentRewards;
    /// @notice Agent bets on operations
    mapping(address agent => mapping(uint256 opHash => Bet bet)) public bets;
    /// @notice Bet type map
    mapping(uint256 opHash => BetType) public betTypes;
    /// @notice Transmitter address for agent that proposed first for given operation (used for additional reward for first agent)
    mapping(uint256 opHash => address transmitter) public firstBet;
    /// @notice Transmitters that bet on given operation
    mapping(uint256 opHash => address[]) public curTransmitters;
    /// @notice Keep transmitter unactivity timeout, after slashingBorder the agent is slashed
    mapping(address transmitter => uint256) public unactiveTransmittersCounter;
    /// @notice Agent statistic with bets and rewards
    mapping(address agent => AgentStatistic) public agentStatistic;
    /// @notice Timestamp when bets of operation were released
    /// @dev Will be used for burning old bets wich were not released
    mapping(uint256 opHash => uint256 timestamp) public opProcessedTimestamp;
    /// @notice protocol reward paid statistic
    mapping(bytes32 protocolId => uint256 rewardPaid) public protocolRewardPaid;

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    /// @param initAddr[1] - Address to discard bets from
    function initialize(address[2] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        _setRoleAdmin(PRUNER, ADMIN);
        _grantRole(PRUNER, initAddr[1]);
    }

    /// @notice Set contracts addresses
    /// @param initAddr[0] - masterSmartContract
    /// @param initAddr[1] - streamDataSpotterFactory
    /// @param initAddr[2] - stakingManager
    /// @param initAddr[3] - agentManager
    /// @param initAddr[4] - externalDeveloperHub
    /// @param initAddr[5] - globalConfig
    function setContracts(address[6] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        masterSmartContract = MasterSmartContract(initAddr[0]);
        _grantRole(BETTER, initAddr[0]); // MasterSmartContract
        _grantRole(BETTER, initAddr[1]); // StreamDataSpotterFactory
        stakingManager = StakingManager(initAddr[2]);
        _grantRole(STAKING_MANAGER, initAddr[2]);
        agentManager = AgentManager(initAddr[3]);
        externalDeveloperHub = ExternalDeveloperHub(initAddr[4]);
        globalConfig = GlobalConfig(initAddr[5]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice Place bet by transmitter on operation (opHash)
    /// @param _protocolId - protocol id
    /// @param _transmitter - Agent's transmitter address for the protocol
    /// @param betType - bet type
    /// @param opHash - operation hash
    function placeBet(
        bytes32 _protocolId,
        address _transmitter,
        BetType betType,
        uint opHash
    ) external onlyRole(BETTER) {
        if (masterSmartContract.isPaused(_protocolId)) {
            revert BetManager__ProtocolIsPaused(_protocolId);
        }

        if (firstBet[opHash] != address(0)) {
            if (betTypes[opHash] != betType) {
                revert BetManager__InvalidBetType(uint(betType));
            }
        } else {
            betTypes[opHash] = betType;
            firstBet[opHash] = _transmitter;
            curTransmitters[opHash] = masterSmartContract.getTransmitters(_protocolId);
        }

        if (externalDeveloperHub.isManualTransmitter(_protocolId, _transmitter)) {
            return;
        }

        address agent = agentManager.agentByTransmitter(_transmitter);
        if (agent == address(0)) {
            revert BetManager__AgentNotFound(_transmitter);
        }
        uint amount = externalDeveloperHub.betAmount(_protocolId, betType);
        bets[agent][opHash].amount += amount;
        if (bets[agent][opHash].timestamp == 0) {
            bets[agent][opHash].timestamp = block.timestamp;
        }
        stakingManager.lockAgentStake(agent, amount);
        agentStatistic[agent].bets++;
        agentStatistic[agent].betsAmount += amount;
    }

    /// @notice Register agent reward for current round
    /// @param _agent - agent address
    /// @param _amount - reward amount
    function registerAgentReward(address _agent, uint _amount) internal {
        for (uint i; i < agentRewards.length; ) {
            if (agentRewards[i].agent == _agent) {
                agentRewards[i].amount += _amount;
                return;
            }
            unchecked {
                ++i;
            }
        }
        agentRewards.push(AgentReward(_agent, _amount));
    }

    /// @notice Release bet after operation executed
    /// @param protocolId - protocol id
    /// @param agentTransmitterBets - array of transmitters that placed bet
    /// @param opHash - operation hash
    function releaseBetsAndReward(
        bytes32 protocolId,
        address[] memory agentTransmitterBets,
        uint opHash
    ) external onlyRole(BETTER) {
        if (firstBet[opHash] == address(0)) {
            revert BetManager__InvalidOpHash(opHash);
        }
        address[] memory unactiveTransmitters = curTransmitters[opHash];
        uint i;
        for (; i < agentTransmitterBets.length; i++) {
            if (externalDeveloperHub.isManualTransmitter(protocolId, agentTransmitterBets[i])) {
                continue;
            }
            address agent = agentManager.agentByTransmitter(agentTransmitterBets[i]);
            if (bets[agent][opHash].amount == 0) {
                continue;
            }
            uint reward = externalDeveloperHub.rewardAmount(
                protocolId,
                betTypes[opHash],
                firstBet[opHash] == agentTransmitterBets[i]
            );
            if (externalDeveloperHub.deduceFee(protocolId, reward)) {
                protocolRewardPaid[protocolId] += reward;
                registerAgentReward(agent, reward);
                agentStatistic[agent].rewards++;
                agentStatistic[agent].rewardsAmount += reward;
            }
            stakingManager.unlockAgentStake(agent, bets[agent][opHash].amount);
            agentStatistic[agent].unlockedAmount += bets[agent][opHash].amount;
            bets[agent][opHash].amount = 0;
            unactiveTransmittersCounter[agentTransmitterBets[i]] = 0;
            for (uint k; k < unactiveTransmitters.length; ) {
                if (unactiveTransmitters[k] == agentTransmitterBets[i]) {
                    unactiveTransmitters[k] = address(0);
                    break;
                }
                unchecked {
                    ++k;
                }
            }
        }
        opProcessedTimestamp[opHash] = block.timestamp;
        // slash
        delete i;
        for (; i < unactiveTransmitters.length; i++) {
            if (
                unactiveTransmitters[i] == address(0) ||
                externalDeveloperHub.isManualTransmitter(protocolId, unactiveTransmitters[i])
            ) {
                continue;
            }
            ++unactiveTransmittersCounter[unactiveTransmitters[i]];
            if (
                unactiveTransmittersCounter[unactiveTransmitters[i]] >=
                globalConfig.slashingBorder()
            ) {
                slash(unactiveTransmitters[i], externalDeveloperHub.minPersonalAmount(protocolId));
                masterSmartContract.removeTransmitter(protocolId, unactiveTransmitters[i]);
                unactiveTransmittersCounter[unactiveTransmitters[i]] = 0;
            }
        }
        // Take protocol fee
        if (protocolId != masterSmartContract.govProtocolId()) {
            uint pf = externalDeveloperHub.protocolFee(protocolId);
            if (externalDeveloperHub.deduceFee(protocolId, pf)) {
                stakingManager.creditSystemFee(pf);
            }
        }
    }

    /// @notice Refund bet if agent's proof was rotten after round changing
    /// @param protocolId - protocol id
    /// @param opHash - operation hash
    /// @param transmitter - transmitter address
    function refundBet(
        bytes32 protocolId,
        uint opHash,
        address transmitter
    ) external onlyRole(BETTER) {
        if (firstBet[opHash] == address(0)) {
            revert BetManager__InvalidOpHash(opHash);
        }
        if (externalDeveloperHub.isManualTransmitter(protocolId, transmitter)) {
            return;
        }
        address agent = agentManager.agentByTransmitter(transmitter);
        if (bets[agent][opHash].amount == 0) {
            return;
        }

        stakingManager.unlockAgentStake(agent, bets[agent][opHash].amount);
        agentStatistic[agent].unlockedAmount += bets[agent][opHash].amount;
        bets[agent][opHash].amount = 0;
    }

    /// @notice Slash agent stake
    /// @param _transmitter - agent's transmitter address
    /// @param _amount - amount to slash
    function slash(address _transmitter, uint _amount) internal {
        address agent = agentManager.agentByTransmitter(_transmitter);
        if (agent != address(0)) {
            stakingManager.slash(agent, _amount);
        }
    }

    /// @notice Get reward list for current round, reset reward list after that
    function takeAgentRewards() external onlyRole(STAKING_MANAGER) returns (AgentReward[] memory) {
        AgentReward[] memory rewards = agentRewards;
        delete agentRewards;
        return rewards;
    }

    /// @notice Void agent bet and transfer to feeCollector
    function pruneBet(address agent, uint256 opHash) external onlyRole(PRUNER) {
        if (bets[agent][opHash].amount == 0) {
            revert BetManager__TryingToDiscardZeroBet();
        }
        if (block.timestamp - bets[agent][opHash].timestamp < globalConfig.betTimeout()) {
            revert BetManager__TimeoutNotElapsed();
        }
        stakingManager.creditSystemFee(bets[agent][opHash].amount);
        bets[agent][opHash].amount = 0;
    }
}
