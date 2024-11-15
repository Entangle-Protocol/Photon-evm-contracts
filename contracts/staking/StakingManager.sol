//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./AgentManager.sol";
import "./GlobalConfig.sol";
import "../lib/OrderedListUINT.sol";
import "../interfaces/IWNGL.sol";

// This contract implements delegation logic for agent staking, which is based on delegated proof of stake.
// User delegates some amount to a agent, which will accure rewards starting from next round.
// To withdraw user must specify requested withdrawal amount which will be available to withdraw on next round.
// After each round users and validators (agents) can claim their rewards.
contract StakingManager is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    using OrderedListUINT for OrderedListUINT.List;

    error StakingManager__IsNotApprovedAgent(address);
    error StakingManager__AgentIsNotActive(address);
    error StakingManager__RewardsAlreadyClaimed();
    error StakingManager__ZeroAmount();
    error StakingManager__InsufficientStake();
    error StakingManager__InsufficientPersonalStake(address agent, uint lockAmount);
    error StakingManager__UnlockTooMuch(address agent, uint unlockAmount);
    error StakingManager__InvalidFeeRate(uint);
    error StakingManager__InvalidRoundCondition();
    error StakingManager__NoWithdrawRequested();
    error StakingManager__WithdrawingPended();
    error StakingManager__InvalidInputLength();
    error StakingManager__IsNotFeeCollector();
    error StakingManager__TryingToWithdrawTooMuch();

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant ROUND_MANAGER = keccak256("ROUND_MANAGER");
    bytes32 public constant TRANSFER_AND_CREDIT = keccak256("TRANSFER_AND_CREDIT");
    bytes32 public constant AB_MANAGER = keccak256("AB_MANAGER"); // AgentManager & BetManager

    event Delegate(
        address indexed delegator,
        address indexed agent,
        uint indexed round,
        uint amount
    );
    event Withdraw(
        address indexed delegator,
        address indexed agent,
        uint indexed round,
        uint amount
    );
    event Redelegate(
        address indexed delegator,
        address from,
        address to,
        uint indexed round,
        uint amount
    );

    event RewardClaimed(
        address indexed delegator,
        address indexed agent,
        address rewardCollector,
        uint amount
    );
    event AgentRewardClaimed(address indexed agent, address rewardCollector, uint amount);
    event UpdateFee(address indexed agent, uint round, uint fee);
    event DepositPersonalStake(address indexed agent, uint round, uint amount);
    event RequestWithdrawPersonalStake(address indexed agent, uint round, uint amount);
    event CancelWithdrawPersonalStake(address indexed agent, uint round, uint amount);
    event WithdrawPersonalStake(address indexed agent, uint round, uint amount);
    event Slashed(address indexed agent, uint round, uint amount);

    struct Reward {
        uint agentReward;
        uint delegateReward;
        uint totalDelegate;
        bool slashed;
    }

    struct Delegator {
        uint stake;
        uint lastStakeUnstakeRound;
        uint lastClaimRound;
    }

    struct AgentInfo {
        /// @notice Current active total delegation for agent (would be active on next round)
        uint realtimeStake;
        /// @notice Active total delegation at the start of round
        uint activeRoundStake;
        /// @notice Current fee set by agent (activated on next round) 10000 = 100%
        uint realtimeFee;
        /// @notice Active fee
        uint activeRoundFee;
        /// @notice Agent personal deposit
        uint personalStake;
        /// @notice Amount requested for withdraw
        uint withdrawRequestAmount;
        /// @notice Amount ready for withdraw
        uint withdrawReadyAmount;
        /// @notice Rewards claimed on x round
        uint lastClaimRound;
        /// @notice Slashed on x round
        uint lastSlashRound;
        /// @notice Rewards by round
        mapping(uint round => Reward) rewards;
        /// @notice Delegator list
        mapping(address => Delegator) delegators;
    }

    /// @notice setContracts init marker
    bool isInit;
    AgentManager agentManager;
    BetManager betManager;
    ExternalDeveloperHub externalDeveloperHub;
    MasterSmartContract masterSmartContract;
    IERC20 ngl;
    GlobalConfig globalConfig;
    /// @notice Current round number
    uint public round;
    /// @notice List of all approved agents
    EnumerableSet.AddressSet private agentsGlobal;
    /// @notice Realtime sorted by total delegation list of all approved agents
    OrderedListUINT.List private agentsSorted;

    /// @notice reward collector addresses for delegators
    mapping(address delegator => mapping(address agent => address rewardCollector))
        public rewardCollectors;
    /// @notice agent info structs
    mapping(address => AgentInfo) agentInfo;

    /// @notice Agent's locked personal stake
    mapping(address agent => uint amount) lockedPersonalStake;

    uint public accumulatedFee;

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    function initialize(address[1] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        round = 1;
        agentsSorted.init(OrderedListUINT.ListType.Descending);
    }

    function isApprovedAgent(address _agent) internal view returns (bool) {
        return agentManager.approvedAgents(_agent);
    }

    modifier onlyApprovedAgent() {
        if (isApprovedAgent(_msgSender()) == false) {
            revert StakingManager__IsNotApprovedAgent(_msgSender());
        }
        _;
    }

    /// @notice Set contracts addresses
    /// @param initAddr[0] - roundManager
    /// @param initAddr[1] - betManager
    /// @param initAddr[2] - agentManager
    /// @param initAddr[3] - externalDeveloperHub
    /// @param initAddr[4] - masterSmartContract
    /// @param initAddr[5] - NGL token address
    /// @param initAddr[6] - globalConfig
    function setContracts(address[7] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        _grantRole(ROUND_MANAGER, initAddr[0]);
        _grantRole(AB_MANAGER, initAddr[1]); // BetManager
        _grantRole(TRANSFER_AND_CREDIT, initAddr[1]); // BetManager
        betManager = BetManager(initAddr[1]);
        _grantRole(AB_MANAGER, initAddr[2]); // AgentManager
        agentManager = AgentManager(initAddr[2]);
        externalDeveloperHub = ExternalDeveloperHub(initAddr[3]);
        _grantRole(TRANSFER_AND_CREDIT, initAddr[3]);
        masterSmartContract = MasterSmartContract(initAddr[4]);
        ngl = IERC20(initAddr[5]);
        globalConfig = GlobalConfig(initAddr[6]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice This methods should also be called before each delegator action (stake/unstake) to keep track of only recent rewards
    /// @param _agent - agent address
    function _claimRewards(address _agent) internal returns (uint) {
        AgentInfo storage _agentInfo = agentInfo[_agent];
        Delegator storage delegator = _agentInfo.delegators[_msgSender()];
        if (delegator.lastClaimRound < delegator.lastStakeUnstakeRound) {
            revert StakingManager__InvalidRoundCondition();
        }
        if (delegator.lastStakeUnstakeRound == 0 || delegator.lastClaimRound == round) {
            delegator.lastClaimRound = round;
            return 0;
        }
        uint totalReward;
        uint _round = round;
        for (uint r = delegator.lastClaimRound; r < _round; ) {
            Reward storage roundReward = _agentInfo.rewards[r];
            if (
                roundReward.totalDelegate != 0 &&
                roundReward.delegateReward != 0 &&
                !roundReward.slashed
            ) {
                totalReward +=
                    (roundReward.delegateReward * delegator.stake) /
                    roundReward.totalDelegate;
            }
            unchecked {
                ++r;
            }
        }
        delegator.lastClaimRound = round;
        address rewardCollector = getRewardCollector(_msgSender(), _agent);
        if (totalReward != 0) {
            ngl.transfer(rewardCollector, totalReward);
        }
        emit RewardClaimed(_msgSender(), _agent, rewardCollector, totalReward);
        return totalReward;
    }

    /// @notice Set reward collector address for delegator
    /// @param rewardCollector - reward collector address
    function setRewardCollector(address agent, address rewardCollector) external {
        if (!isApprovedAgent(agent)) {
            revert StakingManager__IsNotApprovedAgent(agent);
        }
        rewardCollectors[_msgSender()][agent] = rewardCollector;
    }

    /// @notice Get reward collector for delegator
    /// @param delegator - delegator address
    function getRewardCollector(address delegator, address agent) public view returns (address rc) {
        rc = rewardCollectors[delegator][agent];
        if (rc == address(0)) {
            return delegator;
        }
    }

    /// @notice Delegate NGL to agent
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to delegate
    function delegateInternal(address _agent, uint _amount) internal {
        if (_amount == 0) {
            revert StakingManager__ZeroAmount();
        }
        _claimRewards(_agent);
        AgentInfo storage _agentInfo = agentInfo[_agent];

        if (!agentManager.approvedAgents(_agent)) {
            revert StakingManager__AgentIsNotActive(_agent);
        }

        Delegator storage delegator = _agentInfo.delegators[_msgSender()];
        _agentInfo.realtimeStake += _amount;
        agentsSorted.set(abi.encode(_agent), _agentInfo.realtimeStake);
        delegator.stake += _amount;
        delegator.lastStakeUnstakeRound = round;
        emit Delegate(_msgSender(), _agent, round, _amount);
    }

    /// @notice Delegate native and wrapped NGL to agent
    /// @param _agent - agent address
    /// @param _amountWrapped - amount of wrapped NGL to delegate
    function delegateWithNative(address _agent, uint _amountWrapped) external payable nonReentrant {
        uint256 amountTotal = _amountWrapped + msg.value;
        if (msg.value != 0) {
            IWNGL(address(ngl)).deposit{value: msg.value}();
        }
        if (_amountWrapped != 0) {
            ngl.transferFrom(_msgSender(), address(this), _amountWrapped);
        }
        delegateInternal(_agent, amountTotal);
    }

    /// @notice Delegate wrapped NGL to agent
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to delegate
    function delegate(address _agent, uint _amount) external nonReentrant {
        ngl.transferFrom(_msgSender(), address(this), _amount);
        delegateInternal(_agent, _amount);
    }

    /// @notice Withdraw delegation
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to withdraw
    function withdrawInternal(address _agent, uint _amount) internal {
        AgentInfo storage _agentInfo = agentInfo[_agent];
        Delegator storage delegator = _agentInfo.delegators[_msgSender()];
        if (_amount == 0) {
            revert StakingManager__ZeroAmount();
        }
        if (_amount > delegator.stake) {
            revert StakingManager__InsufficientStake();
        }
        _claimRewards(_agent);
        _agentInfo.realtimeStake -= _amount;
        agentsSorted.set(abi.encode(_agent), _agentInfo.realtimeStake);
        delegator.stake -= _amount;
        delegator.lastStakeUnstakeRound = round;
        emit Withdraw(_msgSender(), _agent, round, _amount);
    }

    /// @notice Withdraw delegation
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to withdraw
    function withdraw(address _agent, uint _amount) external nonReentrant {
        withdrawInternal(_agent, _amount);
        ngl.transfer(_msgSender(), _amount);
    }

    /// @notice Transfer delegation to another agent
    /// @param _from - transfer from agent
    /// @param _to - transfer to agent
    /// @param _amount - amount of NGL to transfer
    function redelegate(address _from, address _to, uint _amount) external nonReentrant {
        withdrawInternal(_from, _amount);
        delegateInternal(_to, _amount);
        emit Redelegate(_msgSender(), _from, _to, round, _amount);
    }

    /// @notice Claim delegator rewards from last claim round to current round
    /// @param _agent - agent address
    function claimRewards(address _agent) external nonReentrant returns (uint) {
        return _claimRewards(_agent);
    }

    /// @notice Claim rewards from all delegators
    function claimRewardsAll() external nonReentrant returns (uint) {
        uint total = 0;
        for (uint i = 0; i < agentsGlobal.length(); ) {
            total += _claimRewards(agentsGlobal.at(i));
            unchecked {
                ++i;
            }
        }
        return total;
    }

    /// @notice Claim accumulated system fees
    function claimSystemFees() external {
        if (_msgSender() != globalConfig.feeCollector()) {
            revert StakingManager__IsNotFeeCollector();
        }
        ngl.transfer(_msgSender(), accumulatedFee);
        accumulatedFee = 0;
    }

    /// @notice Distribute rewards at the turn of a round
    function distributeRewards() external onlyRole(ROUND_MANAGER) {
        BetManager.AgentReward[] memory rewards = betManager.takeAgentRewards();
        uint totalFee;
        uint agentRewardFee = globalConfig.agentRewardFee();
        for (uint i; i < rewards.length; ) {
            address agentAddr = rewards[i].agent;
            uint rewardAmount = rewards[i].amount;
            AgentInfo storage agent = agentInfo[agentAddr];
            Reward storage reward = agent.rewards[round];
            if (reward.slashed) {
                totalFee += rewardAmount;
            } else {
                uint fee = (rewardAmount * agentRewardFee) / 10000;
                totalFee += fee;
                uint amount = rewardAmount - fee;
                uint _agentReward = (amount * agent.activeRoundFee) / 10000;
                reward.agentReward += _agentReward;
                reward.delegateReward += amount - _agentReward;
            }
            unchecked {
                ++i;
            }
        }
        accumulatedFee += totalFee;
    }

    /// @notice Execute turning of a round
    function turnRound() external onlyRole(ROUND_MANAGER) {
        for (uint i; i < agentsGlobal.length(); ) {
            AgentInfo storage agent = agentInfo[agentsGlobal.at(i)];
            agent.activeRoundStake = agent.realtimeStake;
            agent.rewards[round].totalDelegate = agent.realtimeStake;
            agent.activeRoundFee = agent.realtimeFee;
            if (agent.withdrawRequestAmount > 0) {
                uint ready = agent.withdrawRequestAmount > agent.personalStake
                    ? agent.personalStake
                    : agent.withdrawRequestAmount;
                agent.personalStake -= ready;
                agent.withdrawReadyAmount += ready;
                agent.withdrawRequestAmount = 0;
            }
            unchecked {
                ++i;
            }
        }
        ++round;
    }

    /// @notice Lock agent stake for bet
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to lock
    function lockAgentStake(address _agent, uint _amount) external onlyRole(AB_MANAGER) {
        AgentInfo storage agent = agentInfo[_agent];
        if (agent.personalStake < _amount) {
            revert StakingManager__InsufficientPersonalStake(_agent, _amount);
        }
        agent.personalStake -= _amount;
        lockedPersonalStake[_agent] += _amount;
    }

    /// @notice Unlock agent stake when bet is released
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to unlock
    function unlockAgentStake(address _agent, uint _amount) external onlyRole(AB_MANAGER) {
        AgentInfo storage agent = agentInfo[_agent];
        agent.personalStake += _amount;
        if (_amount > lockedPersonalStake[_agent]) {
            revert StakingManager__UnlockTooMuch(_agent, _amount);
        }
        lockedPersonalStake[_agent] -= _amount;
    }

    /// @notice Slash agent personal stake
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to slash
    function slash(address _agent, uint _amount) external onlyRole(AB_MANAGER) {
        AgentInfo storage agent = agentInfo[_agent];
        if (agent.personalStake >= _amount) {
            agent.personalStake -= _amount;
            accumulatedFee += _amount;
        } else {
            accumulatedFee += agent.personalStake;
            agent.personalStake = 0;
        }
        agent.rewards[round].slashed = true;
        emit Slashed(_agent, round, _amount);
    }

    /// @notice Claim agent rewards from last claim round to current round
    function claimAgentRewards() external nonReentrant onlyApprovedAgent {
        AgentInfo storage agent = agentInfo[_msgSender()];
        if (round <= agent.lastClaimRound) {
            revert StakingManager__RewardsAlreadyClaimed();
        }
        uint totalReward;
        uint _round = round;
        for (uint i = agent.lastClaimRound; i < _round; ) {
            if (!agent.rewards[i].slashed) {
                totalReward += agent.rewards[i].agentReward;
            }
            unchecked {
                ++i;
            }
        }
        agent.lastClaimRound = round;
        address rewardCollector = agentManager.rewardAddress(_msgSender());
        if (totalReward != 0) {
            ngl.transfer(rewardCollector, totalReward);
        }
        emit AgentRewardClaimed(_msgSender(), rewardCollector, totalReward);
    }

    /// @notice Update agent fee (reflected only on next round)
    /// @param newFee - new fee
    function updateFee(uint newFee) external onlyApprovedAgent {
        if (newFee > 10000) {
            revert StakingManager__InvalidFeeRate(newFee);
        }
        if (newFee == agentInfo[_msgSender()].realtimeFee) {
            return;
        }
        agentInfo[_msgSender()].realtimeFee = newFee;
        emit UpdateFee(_msgSender(), round, newFee);
    }

    /// @notice Deposit to personal stake of agent
    /// @param _amount - amount of NGL to deposit
    function depositPersonalStake(uint _amount) external nonReentrant onlyApprovedAgent {
        if (_amount == 0) {
            revert StakingManager__ZeroAmount();
        }
        ngl.transferFrom(_msgSender(), address(this), _amount);
        agentInfo[_msgSender()].personalStake += _amount;
        emit DepositPersonalStake(_msgSender(), round, _amount);
    }

    /// @notice Deposit to personal stake of agent from admin balance
    /// @param _agent - agent address
    /// @param _amount - amount of NGL to deposit
    function depositPersonalStakeByAdmin(
        address _agent,
        uint _amount
    ) external nonReentrant onlyRole(ADMIN) {
        if (_amount == 0) {
            revert StakingManager__ZeroAmount();
        }
        if (!isApprovedAgent(_agent)) {
            revert StakingManager__IsNotApprovedAgent(_agent);
        }
        ngl.transferFrom(_msgSender(), address(this), _amount);
        agentInfo[_agent].personalStake += _amount;
        emit DepositPersonalStake(_agent, round, _amount);
    }

    /// @notice Request withdrawal from personal stake of agent (available to withdraw on next round)
    /// @param _amount - amount of NGL to withdraw
    function requestWithdrawPersonalStake(uint _amount) external onlyApprovedAgent {
        if (_amount == 0) {
            revert StakingManager__ZeroAmount();
        }
        agentInfo[_msgSender()].withdrawRequestAmount += _amount;
        if (
            agentInfo[_msgSender()].withdrawRequestAmount >
            agentInfo[_msgSender()].personalStake + lockedPersonalStake[_msgSender()]
        ) {
            revert StakingManager__TryingToWithdrawTooMuch();
        }
        emit RequestWithdrawPersonalStake(_msgSender(), round, _amount);
    }

    /// @notice Cancel withdraw request
    function cancelWithdrawPersonalStake() external onlyApprovedAgent {
        emit RequestWithdrawPersonalStake(
            _msgSender(),
            round,
            agentInfo[_msgSender()].withdrawRequestAmount
        );
        agentInfo[_msgSender()].withdrawRequestAmount = 0;
    }

    /// @notice Withdraw personal stake (requested on previous rounds)
    function withdrawPersonalStake() external nonReentrant onlyApprovedAgent {
        if (agentInfo[_msgSender()].withdrawReadyAmount == 0) {
            revert StakingManager__NoWithdrawRequested();
        }
        ngl.transfer(_msgSender(), agentInfo[_msgSender()].withdrawReadyAmount);
        agentInfo[_msgSender()].withdrawReadyAmount = 0;
        emit WithdrawPersonalStake(
            _msgSender(),
            round,
            agentInfo[_msgSender()].withdrawReadyAmount
        );
    }

    /// @notice Add agent to the list
    function addAgent(address agent) external onlyRole(AB_MANAGER) returns (bool) {
        bool isNew = agentsGlobal.add(agent);
        if (isNew) {
            agentsSorted.set(abi.encode(agent), 0);
        }
        return isNew;
    }

    /// @notice Remove agent from the list
    function removeAgent(address agent) external onlyRole(AB_MANAGER) returns (bool) {
        return agentsGlobal.remove(agent);
    }

    /// @notice Check if agent exists
    function isAgentExists(address agent) external view returns (bool) {
        return agentsGlobal.contains(agent);
    }

    /// @notice Add accumulated fee
    function creditSystemFee(uint amount) external onlyRole(TRANSFER_AND_CREDIT) {
        accumulatedFee += amount;
    }

    /// @notice Transfer tokens to address
    /// @param to - address to transfer
    /// @param amount - amount to transfer
    /// @dev no need nonReentrant modifier here, cant be called from not allowed roles
    function transferTo(
        address to,
        uint amount
    ) external nonReentrant onlyRole(TRANSFER_AND_CREDIT) {
        ngl.transfer(to, amount);
    }

    /// @notice Select agent (transmitter) addresses for protocol
    /// @param protocolId - protocol id
    /// @param agents - max amount of transmitters to select
    function selectAgentsTransmitters(
        bytes32 protocolId,
        uint agents,
        address[] memory cachedAgents
    ) internal view returns (address[] memory) {
        uint minPersonalStake = externalDeveloperHub.minPersonalAmount(protocolId);
        uint minTotalDelegation = externalDeveloperHub.minDelegateAmount(protocolId);
        address[] memory selected = new address[](agents);
        uint n;
        uint i;
        while (i < cachedAgents.length && n < agents) {
            address agentAddr = cachedAgents[i];
            //require(agentAddr != address(0), "Test: agent address should not be 0");
            AgentInfo storage agent = agentInfo[agentAddr];
            if (
                agentManager.protocolSupported(agentAddr, protocolId) &&
                agentsGlobal.contains(agentAddr) &&
                agent.activeRoundStake >= minTotalDelegation &&
                agent.personalStake >= minPersonalStake &&
                agentManager.pausedAgents(agentAddr) == false
            ) {
                address transmitter = agentManager.transmitters(agentAddr, protocolId);
                /*require(
                    transmitter != address(0),
                    "Test: transmitter should always exist at that point"
                );*/
                selected[n] = transmitter;
                unchecked {
                    ++n;
                }
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(selected, n)
        }
        return selected;
    }

    /// @notice Select agent (transmitter) addresses for protocol both manual and from agents
    /// @param protocolId - protocol id
    function selectTransmittersForProtocol(
        bytes32 protocolId,
        address[] memory cachedAgents
    ) internal view returns (address[] memory) {
        address[] memory manualTransmitters = externalDeveloperHub.manualTransmitters(protocolId);
        if (protocolId == masterSmartContract.govProtocolId()) {
            return manualTransmitters;
        }
        uint slots = externalDeveloperHub.maxTransmitters(protocolId);
        address[] memory transmitters = new address[](slots);
        uint n;
        uint i;
        while (i < manualTransmitters.length && n < slots) {
            transmitters[n] = manualTransmitters[i];
            unchecked {
                ++i;
                ++n;
            }
        }
        // Select public agents transmitters
        address[] memory selected = selectAgentsTransmitters(protocolId, slots - n, cachedAgents);
        delete i;
        while (n < slots && i < selected.length) {
            transmitters[n] = selected[i];
            unchecked {
                ++i;
                ++n;
            }
        }
        assembly {
            mstore(transmitters, n)
        }
        return transmitters;
    }

    /// @notice Update protocol agents and transmitters for given protocols
    /// @param protocols - protocols array
    function updateAgents(bytes32[] memory protocols) external onlyRole(ROUND_MANAGER) {
        address[] memory cachedAgents = agentsSorted.getAsAddress();
        uint i;
        while (i < protocols.length) {
            address[] memory transmitters = selectTransmittersForProtocol(
                protocols[i],
                cachedAgents
            );
            masterSmartContract.updateTransmitters(protocols[i], transmitters);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get actual total delegation (recorded at the start of round)
    /// @param _agent - agent address
    function getAgentActiveDelegation(address _agent) external view returns (uint) {
        return agentInfo[_agent].activeRoundStake;
    }

    /// @notice Get current total delegation (reflected on the next round)
    /// @param _agent - agent address
    function getAgentRealtimeDelegation(address _agent) external view returns (uint) {
        return agentInfo[_agent].realtimeStake;
    }

    /// @notice Get personal stake of agent
    /// @param _agent - agent address
    function getAgentPersonalStake(address _agent) external view returns (uint) {
        return agentInfo[_agent].personalStake;
    }

    /// @notice Get agent personal stake withdraw request amount (or 0 if not requested)
    /// @param _agent - agent address
    function getAgentPersonalStakeWithdrawRequest(address _agent) external view returns (uint) {
        return agentInfo[_agent].withdrawRequestAmount;
    }

    /// @notice Get agent personal stake withdraw ready amount (or 0 if not requested)
    /// @param _agent - agent address
    function getAgentPersonalStakeWithdrawReady(address _agent) external view returns (uint) {
        return agentInfo[_agent].withdrawReadyAmount;
    }

    /// @notice Get user's rewards per agent
    /// @param _agent - agent address
    /// @param _delegator - delegator address
    function getClaimAmount(address _agent, address _delegator) public view returns (uint) {
        AgentInfo storage _agentInfo = agentInfo[_agent];
        Delegator storage delegator = _agentInfo.delegators[_delegator];
        if (delegator.lastClaimRound < delegator.lastStakeUnstakeRound) {
            return 0;
        }
        if (delegator.lastStakeUnstakeRound == 0 || delegator.lastClaimRound == round) {
            return 0;
        }
        uint totalReward;
        uint _round = round;
        for (uint r = delegator.lastClaimRound; r < _round; ) {
            Reward storage roundReward = _agentInfo.rewards[r];
            if (
                roundReward.totalDelegate != 0 &&
                roundReward.delegateReward != 0 &&
                !roundReward.slashed
            ) {
                totalReward +=
                    (roundReward.delegateReward * delegator.stake) /
                    roundReward.totalDelegate;
            }
            unchecked {
                ++r;
            }
        }
        return totalReward;
    }

    /// @notice Get user's rewards for all agents
    /// @param _delegator - delegator address
    function getTotalClaimAmount(address _delegator) external view returns (uint) {
        uint total = 0;
        for (uint i = 0; i < agentsGlobal.length(); ) {
            total += getClaimAmount(agentsGlobal.at(i), _delegator);
            unchecked {
                ++i;
            }
        }
        return total;
    }

    /// @notice Get agent's rewards
    /// @param _agent - agent address
    function getAgentClaimAmount(address _agent) external view returns (uint) {
        AgentInfo storage agent = agentInfo[_agent];
        if (round <= agent.lastClaimRound) {
            return 0;
        }
        uint totalReward;
        uint _round = round;
        for (uint i = agent.lastClaimRound; i < _round; ) {
            if (!agent.rewards[i].slashed) {
                totalReward += agent.rewards[i].agentReward;
            }
            unchecked {
                ++i;
            }
        }
        return totalReward;
    }

    /// @notice Get agent's delegator info
    /// @param _agent - agent address
    /// @param _delegator - delegator address
    /// @return Delegator struct
    function getDelegatorInfo(
        address _agent,
        address _delegator
    ) external view returns (Delegator memory) {
        return agentInfo[_agent].delegators[_delegator];
    }

    /// @notice Get delegator -> agent delegation
    /// @param _agent - agent address
    /// @param _delegator - delegator address
    /// @return Current delegation by delegator to agent
    function getDelegation(address _agent, address _delegator) external view returns (uint) {
        return agentInfo[_agent].delegators[_delegator].stake;
    }

    /// @notice Get agent fee rates on current and next round (10000 = 100%)
    /// @param _agent - agent address
    /// @return currentRoundFee - fee rate on current round
    /// @return nextRoundFee - fee rate on next round
    function getAgentFeeRates(
        address _agent
    ) external view returns (uint currentRoundFee, uint nextRoundFee) {
        return (agentInfo[_agent].activeRoundFee, agentInfo[_agent].realtimeFee);
    }

    function getAgents() external view returns (address[] memory) {
        return agentsSorted.getAsAddress();
    }
}
