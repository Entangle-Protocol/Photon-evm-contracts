//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";

contract GlobalConfig is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN = keccak256("ADMIN");

    error GlobalConfig__InvalidAgentRewardFee();
    error GlobalConfig__InvalidBetTimeout();

    /// @notice Fee collector address for entangle protocol
    address public feeCollector;
    /// @notice Deduced when external developer registers a new protocol
    uint public protocolRegisterFee;
    /// @notice Deduced for each new agent that is not already exists in manualAgents
    uint public manualTransmitterFee;
    /// @notice Deduced on each call to any function that changes protocol params (except changing manual agents)
    uint public changeProtocolParamsFee;
    /// @notice Minimum protocol balance, otherwise protocol is not considered active and paused
    uint public minProtocolBalance;
    /// @notice Maximum number of agents a protocol can have (including manual agents)
    uint public maxTransmittersCount;
    /// @notice Fee taken from total rewards to fee collector (100% = 10000)
    uint public agentRewardFee;
    /// @notice Agent stake locked for each transmitter they add
    uint public agentStakePerTransmitter;
    /// @notice Agent inactivity timer threshold
    uint public slashingBorder;
    /// @notice Default fee for operation
    uint public protocolOperationFee;
    /// @notice Protocol init fee when new chain is added
    uint public initNewChainFee;
    /// @notice Minimum timeout for taking rotted bets
    uint public betTimeout;
    /// @notice Minimum time before round can be turned
    uint public minRoundTime;

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    function initialize(address[1] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        betTimeout = 30 days;
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    function setConfig(
        address _feeCollector,
        uint _protocolRegisterFee,
        uint _manualTransmitterFee,
        uint _changeProtocolParamsFee,
        uint _minProtocolBalance,
        uint _maxTransmittersCount,
        uint _agentRewardFee,
        uint _agentStakePerTransmitter,
        uint _slashingBorder,
        uint _protocolOperationFee,
        uint _initNewChainFee,
        uint _betTimeout,
        uint _minRoundTime
    ) external onlyRole(ADMIN) {
        if (_agentRewardFee > 10000) {
            revert GlobalConfig__InvalidAgentRewardFee();
        }
        if (_betTimeout < 30 days) {
            revert GlobalConfig__InvalidBetTimeout();
        }
        feeCollector = _feeCollector;
        protocolRegisterFee = _protocolRegisterFee;
        manualTransmitterFee = _manualTransmitterFee;
        changeProtocolParamsFee = _changeProtocolParamsFee;
        minProtocolBalance = _minProtocolBalance;
        maxTransmittersCount = _maxTransmittersCount;
        agentRewardFee = _agentRewardFee;
        agentStakePerTransmitter = _agentStakePerTransmitter;
        slashingBorder = _slashingBorder;
        protocolOperationFee = _protocolOperationFee;
        initNewChainFee = _initNewChainFee;
        betTimeout = _betTimeout;
        minRoundTime = _minRoundTime;
    }

    function setFeeCollector(address _feeCollector) external onlyRole(ADMIN) {
        feeCollector = _feeCollector;
    }

    function setProtocolRegisterFee(uint _protocolRegisterFee) external onlyRole(ADMIN) {
        protocolRegisterFee = _protocolRegisterFee;
    }

    function setManualAgentFee(uint _manualTransmitterFee) external onlyRole(ADMIN) {
        manualTransmitterFee = _manualTransmitterFee;
    }

    function setChangeProtocolParamsFee(uint _changeProtocolParamsFee) external onlyRole(ADMIN) {
        changeProtocolParamsFee = _changeProtocolParamsFee;
    }

    function setMinProtocolBalance(uint _minProtocolBalance) external onlyRole(ADMIN) {
        minProtocolBalance = _minProtocolBalance;
    }

    function setMaxTransmittersCount(uint _maxTransmittersCount) external onlyRole(ADMIN) {
        maxTransmittersCount = _maxTransmittersCount;
    }

    function setAgentRewardFee(uint _agentRewardFee) external onlyRole(ADMIN) {
        if (_agentRewardFee > 10000) {
            revert GlobalConfig__InvalidAgentRewardFee();
        }
        agentRewardFee = _agentRewardFee;
    }

    function setAgentStakePerTransmitter(uint _agentStakePerTransmitter) external onlyRole(ADMIN) {
        agentStakePerTransmitter = _agentStakePerTransmitter;
    }

    function setSlashingBorder(uint _slashingBorder) external onlyRole(ADMIN) {
        slashingBorder = _slashingBorder;
    }

    function setProtocolOperationFee(uint _protocolOperationFee) external onlyRole(ADMIN) {
        protocolOperationFee = _protocolOperationFee;
    }

    function setInitNewChainFee(uint _initNewChainFee) external onlyRole(ADMIN) {
        initNewChainFee = _initNewChainFee;
    }

    function setBetTimeout(uint _betTimeout) external onlyRole(ADMIN) {
        if (_betTimeout < 30 days) {
            revert GlobalConfig__InvalidBetTimeout();
        }
        betTimeout = _betTimeout;
    }

    function setMinRoundTime(uint _minRoundTime) external onlyRole(ADMIN) {
        minRoundTime = _minRoundTime;
    }
}
