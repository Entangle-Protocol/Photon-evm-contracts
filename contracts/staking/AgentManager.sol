//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./StakingManager.sol";
import "./ExternalDeveloperHub.sol";
import "./GlobalConfig.sol";
import "../MasterSmartContract.sol";

contract AgentManager is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant APPROVER = keccak256("APPROVER");

    error AgentManager__AgentNotApproved();
    error AgentManager__ZeroAddress();
    error AgentManager__MaximumTransmitterCountReached();
    error AgentManager__SupportAlreadyDeclared();
    error AgentManager__SupportNotDeclared();
    error AgentManager__TransmitterAlreadyAdded(address trasmitter, address agent);
    error AgentManager__InvalidProtocolId(bytes32 protocolId);

    event ApproveAgent(address agent, address rewardAddress);
    event BanAgent(address agent);
    event DeclareProtocolSupport(address agent, address transmitter, bytes32 protocolId);
    event RevokeProtocolSupport(address agent, bytes32 protocolId);
    event PauseAgent(address agent);
    event UnpauseAgent(address agent);

    /// @notice setContracts init marker
    bool isInit;
    /// @notice stakingManager
    StakingManager stakingManager;
    /// @notice externalDeveloperHub
    ExternalDeveloperHub externalDeveloperHub;
    /// @notice masterSmartContract
    MasterSmartContract masterSmartContract;
    /// @notice globalConfig
    GlobalConfig globalConfig;

    /// @notice agents approved with KYC
    mapping(address agent => bool) public approvedAgents;
    /// @notice pausedAgents
    mapping(address agent => bool) public pausedAgents;
    /// @notice reward addresses for agents
    mapping(address agent => address) public rewardAddress;
    /// @notice transmitter is agent worker address for protocol
    mapping(address agent => mapping(bytes32 protocolId => address transmitterAddress))
        public transmitters;
    /// @notice agentByTransmitter
    mapping(address transmitter => address agent) public agentByTransmitter;
    /// @notice transmitter count for each agent
    mapping(address agent => uint transmitterCount) public transmitterCount;

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    /// @param initAddr[1] - Approver address
    function initialize(address[2] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        _setRoleAdmin(APPROVER, ADMIN);
        _grantRole(APPROVER, initAddr[1]);
    }

    /// @notice Check if agent is KYC-approve
    modifier isApprovedAgent() {
        if (!approvedAgents[_msgSender()]) {
            revert AgentManager__AgentNotApproved();
        }
        _;
    }

    /// @notice Set contracts addresses
    /// @param initAddr[0] - stakingManager
    /// @param initAddr[1] - externalDeveloperHub
    /// @param initAddr[2] - masterSmartContract
    /// @param initAddr[3] - globalConfig
    function setContracts(address[4] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        stakingManager = StakingManager(initAddr[0]);
        externalDeveloperHub = ExternalDeveloperHub(initAddr[1]);
        masterSmartContract = MasterSmartContract(initAddr[2]);
        globalConfig = GlobalConfig(initAddr[3]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice Approve agent after KYC and set its reward address
    /// @param agent - agent address
    /// @param _rewardAddress - reward address for agent
    function approveAgent(address agent, address _rewardAddress) external onlyRole(APPROVER) {
        stakingManager.addAgent(agent);
        approvedAgents[agent] = true;
        rewardAddress[agent] = _rewardAddress;
        emit ApproveAgent(agent, _rewardAddress);
    }

    /// @notice Ban agent and remove it from protocols and slash full personal stake
    /// @param agent - agent address
    function banAgent(address agent) external onlyRole(APPROVER) {
        approvedAgents[agent] = false;
        stakingManager.slash(agent, stakingManager.getAgentPersonalStake(agent));
        bytes32[] memory protocols = externalDeveloperHub.getProtocols();
        for (uint i; i < protocols.length; ) {
            address transmitter = transmitters[agent][protocols[i]];
            if (transmitter != address(0)) {
                masterSmartContract.removeTransmitter(protocols[i], transmitter);
            }
            unchecked {
                ++i;
            }
        }
        stakingManager.removeAgent(agent);
        emit BanAgent(agent);
    }

    /// @notice Declare protocol support by agent and set transmitter address generated by agent for protocol
    /// @param protocolId - protocol id
    /// @param transmitterAddress - Agent's transmitter address for the protocol
    function declareProtocolSupport(
        bytes32 protocolId,
        address transmitterAddress
    ) external isApprovedAgent {
        if (transmitterAddress == address(0)) {
            revert AgentManager__ZeroAddress();
        }
        if (
            protocolId == bytes32(0) ||
            protocolId == masterSmartContract.govProtocolId() ||
            externalDeveloperHub.getProtocolOwner(protocolId) == address(0)
        ) {
            revert AgentManager__InvalidProtocolId(protocolId);
        }
        if (agentByTransmitter[transmitterAddress] != address(0)) {
            revert AgentManager__TransmitterAlreadyAdded(
                transmitterAddress,
                agentByTransmitter[transmitterAddress]
            );
        }
        uint personalStake = stakingManager.getAgentPersonalStake(_msgSender());
        uint maximumTransmitters = globalConfig.agentStakePerTransmitter() == 0
            ? ~uint256(0)
            : personalStake / globalConfig.agentStakePerTransmitter();
        if (transmitterCount[_msgSender()] >= maximumTransmitters) {
            revert AgentManager__MaximumTransmitterCountReached();
        }
        if (transmitters[_msgSender()][protocolId] != address(0)) {
            revert AgentManager__SupportAlreadyDeclared();
        }
        transmitterCount[_msgSender()] += 1;
        transmitters[_msgSender()][protocolId] = transmitterAddress;
        agentByTransmitter[transmitterAddress] = _msgSender();
        emit DeclareProtocolSupport(_msgSender(), transmitterAddress, protocolId);
    }

    /// @notice Declare protocol support by agent and set transmitter address generated by agent for protocol
    /// @param agent - agent address
    /// @param protocolId - protocol id
    /// @param transmitterAddress - Agent's transmitter address for the protocol
    function declareProtocolSupportByAdmin(
        address agent,
        bytes32 protocolId,
        address transmitterAddress
    ) external onlyRole(ADMIN) {
        if (transmitterAddress == address(0)) {
            revert AgentManager__ZeroAddress();
        }
        if (!approvedAgents[agent]) {
            revert AgentManager__AgentNotApproved();
        }
        if (
            protocolId == bytes32(0) ||
            protocolId == masterSmartContract.govProtocolId() ||
            externalDeveloperHub.getProtocolOwner(protocolId) == address(0)
        ) {
            revert AgentManager__InvalidProtocolId(protocolId);
        }
        if (agentByTransmitter[transmitterAddress] != address(0)) {
            revert AgentManager__TransmitterAlreadyAdded(
                transmitterAddress,
                agentByTransmitter[transmitterAddress]
            );
        }
        uint personalStake = stakingManager.getAgentPersonalStake(agent);
        uint maximumTransmitters = globalConfig.agentStakePerTransmitter() == 0
            ? ~uint256(0)
            : personalStake / globalConfig.agentStakePerTransmitter();
        if (transmitterCount[agent] >= maximumTransmitters) {
            revert AgentManager__MaximumTransmitterCountReached();
        }
        if (transmitters[agent][protocolId] != address(0)) {
            revert AgentManager__SupportAlreadyDeclared();
        }
        transmitterCount[agent] += 1;
        transmitters[agent][protocolId] = transmitterAddress;
        agentByTransmitter[transmitterAddress] = agent;
        emit DeclareProtocolSupport(agent, transmitterAddress, protocolId);
    }

    /// @notice Stop protocol support for given protocol
    /// @param protocolId - protocol id
    function revokeProtocolSupport(bytes32 protocolId) external isApprovedAgent {
        if (transmitters[_msgSender()][protocolId] == address(0)) {
            revert AgentManager__SupportNotDeclared();
        }
        transmitterCount[_msgSender()] -= 1;
        transmitters[_msgSender()][protocolId] = address(0);
        agentByTransmitter[transmitters[_msgSender()][protocolId]] = address(0);
        emit RevokeProtocolSupport(_msgSender(), protocolId);
    }

    /// @notice Pause agent (self) from participating in next election
    function pauseAgent() external isApprovedAgent {
        pausedAgents[_msgSender()] = true;
        emit PauseAgent(_msgSender());
    }

    /// @notice Pause agent (self) from participating in next election
    /// @param _agent - agent address
    function pauseAgentByAdmin(address _agent) external onlyRole(ADMIN) {
        if (!approvedAgents[_agent]) {
            revert AgentManager__AgentNotApproved();
        }
        pausedAgents[_agent] = true;
        emit PauseAgent(_agent);
    }

    /// @notice Unpause agent (self) and allow it to participate in next election
    function unpauseAgent() external isApprovedAgent {
        pausedAgents[_msgSender()] = false;
        emit UnpauseAgent(_msgSender());
    }

    /// @notice Unpause agent (self) and allow it to participate in next election
    /// @param _agent - agent address
    function unpauseAgentByAdmin(address _agent) external onlyRole(ADMIN) {
        if (!approvedAgents[_agent]) {
            revert AgentManager__AgentNotApproved();
        }
        pausedAgents[_agent] = false;
        emit UnpauseAgent(_agent);
    }

    /// @notice Check if agent supports protocol
    /// @param _agent - agent address
    /// @param _protocolId - protocol id
    function protocolSupported(address _agent, bytes32 _protocolId) external view returns (bool) {
        return transmitters[_agent][_protocolId] != address(0);
    }
}
