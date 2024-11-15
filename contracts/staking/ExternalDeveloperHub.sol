//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../MasterSmartContract.sol";
import "./BetManager.sol";
import "./StakingManager.sol";
import "./GlobalConfig.sol";
import "../lib/OperationLib.sol";

contract ExternalDeveloperHub is Initializable, UUPSUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    error ExternalDeveloperHub__ChainIsNotSupported(uint);
    error ExternalDeveloperHub__IsNotOwner(bytes32, address);
    error ExternalDeveloperHub__ProtocolNotRegistered(bytes32);
    error ExternalDeveloperHub__ExternalDeveloperNotApproved(address);
    error ExternalDeveloperHub__AddrTooBig(bytes32);
    error ExternalDeveloperHub__ProtocolAlreadyExists(bytes32);
    error ExternalDeveloperHub__ProtocolNotActive();
    error ExternalDeveloperHub__NothingToClaim();
    error ExternalDeveloperHub__DuplicateTransmitter(address);
    error ExternalDeveloperHub__ZeroAmount();
    error ExternalDeveloperHub__ZeroOwner();
    error ExternalDeveloperHub__ZeroAddress();
    error ExternalDeveloperHub__InvalidAddress(bytes);
    error ExternalDeveloperHub__NoTransmittersAllowed();
    error ExternalDeveloperHub__InsufficientFunds();
    error ExternalDeveloperHub__InvalidConsensusTargetRate(uint);
    error ExternalDeveloperHub__ManualTransmittersLimitExceeded();
    error ExternalDeveloperHub__MaxTransmittersLimitTooHigh();
    error ExternalDeveloperHub__ZeroGovExecutors(bytes32, uint);
    error ExternalDeveloperHub__TransmitterFromAnotherProtocol(address, bytes32);

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant APPROVER = keccak256("APPROVER");
    bytes32 public constant BET_MANAGER = keccak256("BET_MANAGER");
    bytes32 public constant ROUND_MANAGER = keccak256("ROUND_MANAGER");

    event ApproveExternalDeveloper(address externalDeveloper);
    event RemoveExternalDeveloper(address externalDeveloper);
    event SetMaxTransmitterLimitByAdmin(bytes32 indexed protocolId, uint maxTransmitters);
    event SetMaxTransmitterLimit(bytes32 indexed protocolId, uint maxTransmitters);
    event SetMinProtocolBalance(bytes32 indexed protocolId, uint minProtocolBalance);
    event SetProtocolFee(bytes32 indexed protocolId, uint minProtocolBalance);
    event RegisterProtocol(
        address owner,
        bytes32 indexed _protocolId,
        uint _consensusTargetRate,
        uint _minDelegateAmount,
        uint _minPersonalAmount,
        uint _maxTransmitters,
        uint _msgBetAmount,
        uint _dataBetAmount,
        uint _firstMsgBetReward,
        uint _msgBetReward,
        uint _firstDataBetReward,
        uint _dataBetReward,
        address[] _transmitters
    );
    event SetProtocolOwner(bytes32 indexed protocolId, address owner);
    event SetDAOProtocolOwner(bytes32 indexed protocolId, uint chainId, bytes owner);
    event Deposit(bytes32 indexed protocolId, uint amount);
    event SetManualTransmitters(bytes32 indexed protocolId, address[] transmitters);
    event SetConsensusTargetRate(bytes32 indexed protocolId, uint rate);
    event SetMinDelegateAmount(bytes32 indexed protocolId, uint minDelegateAmount);
    event SetMinPersonalAmount(bytes32 indexed protocolId, uint minPersonalAmount);
    event AddAllowedProtocolAddress(
        bytes32 indexed protocolId,
        uint chainId,
        bytes protocolAddress
    );
    event RemoveAllowedProtocolAddress(
        bytes32 indexed protocolId,
        uint chainId,
        bytes protocolAddress
    );
    event AddAllowedProposerAddress(
        bytes32 indexed protocolId,
        uint chainId,
        bytes proposerAddress
    );
    event RemoveAllowedProposerAddress(
        bytes32 indexed protocolId,
        uint chainId,
        bytes proposerAddress
    );
    event AddExecutor(bytes32 indexed protocolId, uint chainId, bytes executor);
    event RemoveExecutor(bytes32 indexed protocolId, uint chainId, bytes executor);

    /// @notice Params that can be updated only on next round.
    struct ProtocolParams {
        uint msgBetAmount;
        uint dataBetAmount;
        uint msgBetReward;
        uint msgBetFirstReward;
        uint dataBetReward;
        uint dataBetFirstReward;
        uint consensusTargetRate;
    }

    /// @notice Params that can be updated anytime and only used on round election.
    struct ProtocolInfo {
        address owner;
        uint fee;
        uint balance;
        uint maxTransmitters;
        uint minDelegateAmount;
        uint minPersonalAmount;
        bool active;
        address[] manualTransmitters;
    }

    /// @notice setContracts init marker
    bool isInit;
    /// @notice externalDevelopers that are KYC verified.
    mapping(address => bool) public approvedExternalDevelopers;
    /// @notice manual max transmitters limit
    mapping(bytes32 protocolId => uint) maxTransmittersLimitByAdmin;
    mapping(bytes32 protocolId => ProtocolInfo) public protocolInfo;
    /// @notice Active params for current round.
    mapping(bytes32 protocolId => ProtocolParams) public activeParams;
    /// @notice Params that will be updated on next round turn.
    mapping(bytes32 protocolId => ProtocolParams) public realtimeParams;
    /// @notice protocol list
    bytes32[] protocols;
    /// @notice Unlocked balance to be claimed
    mapping(address protocolOwner => uint amount) public unlockedBalance;

    MasterSmartContract masterSmartContract;
    StakingManager stakingManager;
    IERC20 ngl;
    GlobalConfig globalConfig;
    /// @notice Minimum balance in stake for specified protocol or it'll be paused
    mapping(bytes32 => uint) public minProtocolBalance;
    /// @notice allowed chains
    mapping(uint chainId => bool allowed) allowedChainIds;

    /// @notice Used to check if gov has at least one executor on given chain
    mapping(uint chainId => uint govExecutors) private govExecutors;

    /// @notice manual transmitter to protocol id mapping
    mapping(address => bytes32) public manualTransmitterToProtocol;

    function _protocolOwnerInternal(bytes32 _protocolId) internal view {
        if (protocolInfo[_protocolId].owner != _msgSender()) {
            revert ExternalDeveloperHub__IsNotOwner(_protocolId, _msgSender());
        }
    }

    modifier protocolOwner(bytes32 _protocolId) {
        _protocolOwnerInternal(_protocolId);
        _;
    }

    modifier allowedChainId(uint _chainId) {
        if (!allowedChainIds[_chainId]) {
            revert ExternalDeveloperHub__ChainIsNotSupported(_chainId);
        }
        _;
    }

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    /// @param initAddr[1] - Approver address
    function initialize(address[2] calldata initAddr) public initializer {
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        _setRoleAdmin(APPROVER, ADMIN);
        _grantRole(APPROVER, initAddr[1]);
    }

    /// @notice Set contracts addresses
    /// @param initAddr[0] - masterSmartContract
    /// @param initAddr[1] - stakingManager
    /// @param initAddr[2] - betManager
    /// @param initAddr[3] - roundManager
    /// @param initAddr[4] - NGL token contract
    /// @param initAddr[5] - globalConfig
    function setContracts(address[6] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        masterSmartContract = MasterSmartContract(initAddr[0]);
        stakingManager = StakingManager(initAddr[1]);
        _grantRole(BET_MANAGER, initAddr[2]);
        _grantRole(ROUND_MANAGER, initAddr[3]);
        ngl = IERC20(initAddr[4]);
        globalConfig = GlobalConfig(initAddr[5]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice Approve externalDeveloper after KYC process
    /// @param externalDeveloper - ExternalDeveloper management address
    function approveExternalDeveloper(address externalDeveloper) external onlyRole(APPROVER) {
        approvedExternalDevelopers[externalDeveloper] = true;
        emit ApproveExternalDeveloper(externalDeveloper);
    }

    /// @notice Remove externalDeveloper from approved list
    /// @param externalDeveloper - ExternalDeveloper management address
    function removeExternalDeveloper(address externalDeveloper) external onlyRole(APPROVER) {
        approvedExternalDevelopers[externalDeveloper] = false;
        emit RemoveExternalDeveloper(externalDeveloper);
    }

    /// @notice Change maximum allowed number of transmitters for protocol (enforced only on next param change by externalDeveloper)
    /// @param _protocolId - Protocol id
    /// @param _maxTransmitters - Maximum allowed transmitters for protocol
    function setMaxTransmitterLimitByAdmin(
        bytes32 _protocolId,
        uint _maxTransmitters
    ) external onlyRole(ADMIN) {
        maxTransmittersLimitByAdmin[_protocolId] = _maxTransmitters;
        emit SetMaxTransmitterLimitByAdmin(_protocolId, _maxTransmitters);
    }

    /// @notice Change minimum balance for protocol
    /// @param _protocolId - Protocol id
    /// @param _minBalance - Minimum balance
    function setMinProtocolBalance(bytes32 _protocolId, uint _minBalance) external onlyRole(ADMIN) {
        minProtocolBalance[_protocolId] = _minBalance;
        emit SetMinProtocolBalance(_protocolId, _minBalance);
    }

    /// @notice Change change protocol fee for specified protocol
    /// @param _protocolId - Protocol id
    /// @param _fee - New protocol fee
    function setProtocolFee(bytes32 _protocolId, uint _fee) external onlyRole(ADMIN) {
        if (protocolInfo[_protocolId].owner == address(0)) {
            revert ExternalDeveloperHub__ProtocolNotRegistered(_protocolId);
        }
        protocolInfo[_protocolId].fee = _fee;
        emit SetProtocolFee(_protocolId, _fee);
    }

    /// @notice Protocols that have minimum balance and not paused
    function getActiveProtocols() external view returns (bytes32[] memory) {
        uint protocols_len = protocols.length;
        bytes32[] memory protocolList = new bytes32[](protocols_len);
        uint n;
        for (uint i; i < protocols_len; ) {
            if (
                !masterSmartContract.isPaused(protocols[i]) &&
                checkProtocolBalance(protocols[i]) &&
                protocolInfo[protocols[i]].active
            ) {
                protocolList[n++] = protocols[i];
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(protocolList, n)
        }
        return protocolList;
    }

    /// @notice Check if all protocol params are valid (should be called after each param setter)
    /// @param _protocolId - Protocol id
    function requireParamsValid(bytes32 _protocolId) public view {
        if (protocolInfo[_protocolId].owner == address(0)) {
            revert ExternalDeveloperHub__ZeroOwner();
        }
        if (!protocolInfo[_protocolId].active) {
            revert ExternalDeveloperHub__ProtocolNotActive();
        }
        if (protocolInfo[_protocolId].manualTransmitters.length == 0) {
            revert ExternalDeveloperHub__NoTransmittersAllowed();
        }
        if (
            realtimeParams[_protocolId].consensusTargetRate <= 5500 ||
            realtimeParams[_protocolId].consensusTargetRate > 10000
        ) {
            revert ExternalDeveloperHub__InvalidConsensusTargetRate(
                uint(realtimeParams[_protocolId].consensusTargetRate)
            );
        }

        if (
            maxTransmittersLimitByAdmin[_protocolId] == 0
                ? protocolInfo[_protocolId].maxTransmitters > globalConfig.maxTransmittersCount()
                : protocolInfo[_protocolId].maxTransmitters >
                    maxTransmittersLimitByAdmin[_protocolId]
        ) {
            revert ExternalDeveloperHub__MaxTransmittersLimitTooHigh();
        }

        // check that manual transmitters count is not more than (100% - consensusTargetRate) * maxTransmitters + 1
        if (
            protocolInfo[_protocolId].manualTransmitters.length >
            (protocolInfo[_protocolId].maxTransmitters *
                (10000 - realtimeParams[_protocolId].consensusTargetRate)) /
                10000 +
                1 &&
            _protocolId != masterSmartContract.govProtocolId()
        ) {
            revert ExternalDeveloperHub__ManualTransmittersLimitExceeded();
        }
    }

    /// @notice Gov protocol (added by Entangle) initialization
    /// @param _minDelegateAmount - Minimum delegate amount for transmitters to participate in protocol
    /// @param _minPersonalAmount - Minimum personal stake amount for transmitters that can participate in protocol
    /// @param _maxTransmitters - Maximum number of transmitters that can participate in protocol
    /// @param _protocolParams - Protocol params
    /// @param _transmitters - List of manual transmitters
    function initGovProtocol(
        address _owner,
        uint _minDelegateAmount,
        uint _minPersonalAmount,
        uint _maxTransmitters,
        ProtocolParams calldata _protocolParams,
        address[] calldata _transmitters
    ) external onlyRole(ADMIN) {
        bytes32 _protocolId = masterSmartContract.govProtocolId();
        protocolInfo[_protocolId].owner = _owner;
        protocolInfo[_protocolId].minDelegateAmount = _minDelegateAmount;
        protocolInfo[_protocolId].minPersonalAmount = _minPersonalAmount;
        protocolInfo[_protocolId].maxTransmitters = _maxTransmitters;
        realtimeParams[_protocolId] = _protocolParams;
        activeParams[_protocolId] = _protocolParams;
        protocolInfo[_protocolId].manualTransmitters = _transmitters;
        for (uint i; i < _transmitters.length; ) {
            manualTransmitterToProtocol[_transmitters[i]] = _protocolId;
            unchecked {
                ++i;
            }
        }
        protocolInfo[_protocolId].active = true;
        protocols.push(_protocolId);
        requireParamsValid(_protocolId);
        masterSmartContract.initGovProtocol(_protocolParams.consensusTargetRate, _transmitters);
    }

    /// @notice set govProtocol address by admin (only once per deploy)
    /// @param _govAddress - Gov protocol address
    /// @param _executors - List of executors
    function addGovProtocolAddress(
        uint _chainId,
        bytes calldata _govAddress,
        bytes[] calldata _executors
    ) external onlyRole(ADMIN) {
        allowedChainIds[_chainId] = true;
        masterSmartContract.addGovProtocolAddress(_chainId, _govAddress, _executors);
    }

    /** ExternalDeveloper admin functions **/

    /// @notice register new protocol (by externalDeveloper)
    /// @param _protocolId - Protocol id
    /// @param _owner - Protocol owner address
    /// @param _minDelegateAmount - Minimum delegate amount for transmitters to participate in protocol
    /// @param _minPersonalAmount - Minimum personal stake amount for transmitters that can participate in protocol
    /// @param _maxTransmitters - Maximum number of transmitters that can participate in protocol
    /// @param _protocolParams - Protocol params
    /// @param _transmitters - List of manual transmitters
    function registerProtocol(
        bytes32 _protocolId,
        address _owner,
        uint _minDelegateAmount,
        uint _minPersonalAmount,
        uint _maxTransmitters,
        ProtocolParams calldata _protocolParams,
        address[] calldata _transmitters
    ) nonReentrant external {
        uint protocolRegFee = globalConfig.protocolRegisterFee();
        if (!ngl.transferFrom(_msgSender(), address(stakingManager), protocolRegFee)) {
            revert ExternalDeveloperHub__InsufficientFunds();
        } else {
            stakingManager.creditSystemFee(protocolRegFee);
        }
        if (!approvedExternalDevelopers[_msgSender()]) {
            revert ExternalDeveloperHub__ExternalDeveloperNotApproved(_msgSender());
        }
        if (protocolInfo[_protocolId].owner != address(0)) {
            revert ExternalDeveloperHub__ProtocolAlreadyExists(_protocolId);
        }
        protocolInfo[_protocolId].owner = _owner;
        protocolInfo[_protocolId].fee = globalConfig.protocolOperationFee();
        protocolInfo[_protocolId].minDelegateAmount = _minDelegateAmount;
        protocolInfo[_protocolId].minPersonalAmount = _minPersonalAmount;
        protocolInfo[_protocolId].maxTransmitters = _maxTransmitters;
        protocolInfo[_protocolId].active = true;
        realtimeParams[_protocolId] = _protocolParams;
        activeParams[_protocolId] = _protocolParams;
        for (uint i; i < _transmitters.length; ) {
            if (_transmitters[i] == address(0)) {
                revert ExternalDeveloperHub__ZeroAddress();
            }
            if (manualTransmitterToProtocol[_transmitters[i]] != bytes32(0)) {
                revert ExternalDeveloperHub__TransmitterFromAnotherProtocol(_transmitters[i], manualTransmitterToProtocol[_transmitters[i]]);
            }
            manualTransmitterToProtocol[_transmitters[i]] = _protocolId;
            protocolInfo[_protocolId].manualTransmitters.push(_transmitters[i]);
            unchecked {
                ++i;
            }
        }
        protocols.push(_protocolId);
        requireParamsValid(_protocolId);
        masterSmartContract.addProtocol(_protocolId, _protocolParams.consensusTargetRate);
        emit RegisterProtocol(
            _owner,
            _protocolId,
            _protocolParams.consensusTargetRate,
            _minDelegateAmount,
            _minPersonalAmount,
            _maxTransmitters,
            _protocolParams.msgBetAmount,
            _protocolParams.dataBetAmount,
            _protocolParams.msgBetFirstReward,
            _protocolParams.msgBetReward,
            _protocolParams.dataBetFirstReward,
            _protocolParams.dataBetReward,
            _transmitters
        );
    }

    /// @notice Deduce fee from externalDeveloper on each function that changes protocol params
    function deduceChangeParamsFee(bytes32 _protocolId) internal {
        if (_protocolId == masterSmartContract.govProtocolId()) {
            return;
        }
        uint fee = globalConfig.changeProtocolParamsFee();
        if (fee > 0) {
            if (!(checkProtocolBalance(_protocolId) && protocolInfo[_protocolId].balance >= fee)) {
                revert ExternalDeveloperHub__InsufficientFunds();
            }
            protocolInfo[_protocolId].balance -= fee;
            stakingManager.creditSystemFee(fee);
        }
    }

    /// @notice Transfer ownership to new externalDeveloper address
    /// @param _protocolId - Protocol id
    /// @param newOwner - New owner address
    function setProtocolOwner(
        bytes32 _protocolId,
        address newOwner
    ) external protocolOwner(_protocolId) {
        protocolInfo[_protocolId].owner = newOwner;
        requireParamsValid(_protocolId);
        emit SetProtocolOwner(_protocolId, newOwner);
    }

    /// @notice Set minimum personal stake amount for transmitters that can participate in protocol
    /// @param _protocolId - Protocol id
    /// @param _minPersonalAmount - Minimum personal stake amount
    function setMinPersonalAmount(
        bytes32 _protocolId,
        uint256 _minPersonalAmount
    ) external protocolOwner(_protocolId) {
        protocolInfo[_protocolId].minPersonalAmount = _minPersonalAmount;
        requireParamsValid(_protocolId);
        emit SetMinPersonalAmount(_protocolId, _minPersonalAmount);
    }

    /// @notice Set minimum delegate amount for transmitters to participate in protocol
    /// @param _protocolId - Protocol id
    /// @param _minDelegateAmount - Minimum delegate amount
    function setMinDelegateAmount(
        bytes32 _protocolId,
        uint256 _minDelegateAmount
    ) external protocolOwner(_protocolId) {
        protocolInfo[_protocolId].minDelegateAmount = _minDelegateAmount;
        requireParamsValid(_protocolId);
        emit SetMinDelegateAmount(_protocolId, _minDelegateAmount);
    }

    /// @notice Set maximum number of transmitters that can participate in protocol
    /// @param _protocolId - Protocol id
    /// @param _maxTransmitters - Maximum number of transmitters
    function setMaxTransmitterLimit(
        bytes32 _protocolId,
        uint _maxTransmitters
    ) external protocolOwner(_protocolId) {
        protocolInfo[_protocolId].maxTransmitters = _maxTransmitters;
        requireParamsValid(_protocolId);
        emit SetMaxTransmitterLimit(_protocolId, _maxTransmitters);
    }

    /// @notice Set protocol bet and reward params
    /// @param _protocolId - Protocol id
    /// @param _protocolParams - Protocol params
    function setProtocolParams(
        bytes32 _protocolId,
        ProtocolParams calldata _protocolParams
    ) external protocolOwner(_protocolId) {
        deduceChangeParamsFee(_protocolId);
        realtimeParams[_protocolId] = _protocolParams;
        requireParamsValid(_protocolId);
    }

    /// @notice Deposit NGL to protocol balance
    /// @param _protocolId - Protocol id
    /// @param _amount - Amount of NGL to deposit
    function deposit(bytes32 _protocolId, uint _amount) nonReentrant external protocolOwner(_protocolId) {
        if (_amount == 0) {
            revert ExternalDeveloperHub__ZeroAmount();
        }
        if (!ngl.transferFrom(_msgSender(), address(stakingManager), _amount)) {
            revert ExternalDeveloperHub__InsufficientFunds();
        }
        protocolInfo[_protocolId].balance += _amount;
        if (checkProtocolBalance(_protocolId)) {
            masterSmartContract.setProtocolPause(_protocolId, false);
        }
        requireParamsValid(_protocolId);
        emit Deposit(_protocolId, _amount);
    }

    /// @notice Set manual transmitter list
    /// @param _protocolId - Protocol id
    /// @param _transmitters - List of transmitter addresses
    function setManualTransmitters(
        bytes32 _protocolId,
        address[] calldata _transmitters
    ) external protocolOwner(_protocolId) {
        if (_transmitters.length == 0) {
            revert ExternalDeveloperHub__NoTransmittersAllowed();
        }
        uint i;
        for (; i < _transmitters.length; ) {
            if (_transmitters[i] == address(0)) {
                revert ExternalDeveloperHub__ZeroAddress();
            }
            if (manualTransmitterToProtocol[_transmitters[i]] != bytes32(0) && manualTransmitterToProtocol[_transmitters[i]] != _protocolId) {
                revert ExternalDeveloperHub__TransmitterFromAnotherProtocol(_transmitters[i], manualTransmitterToProtocol[_transmitters[i]]);
            }
            else {
                manualTransmitterToProtocol[_transmitters[i]] = _protocolId;
            }
            for (uint k; k < _transmitters.length; ) {
                if (i != k && _transmitters[i] == _transmitters[k]) {
                    revert ExternalDeveloperHub__DuplicateTransmitter(_transmitters[i]);
                }
                unchecked {
                    ++k;
                }
            }
            unchecked {
                ++i;
            }
        }
        delete i;
        if (_protocolId != masterSmartContract.govProtocolId()) {
            uint newTransmittersFee = globalConfig.manualTransmitterFee();
            uint totalFee;
            for (; i < _transmitters.length; ) {
                bool found;
                address[] memory manualTransmittersArr = protocolInfo[_protocolId]
                    .manualTransmitters;
                for (uint j; j < manualTransmittersArr.length; ) {
                    if (manualTransmittersArr[j] == _transmitters[i]) {
                        found = true;
                        break;
                    }
                    unchecked {
                        ++j;
                    }
                }
                if (!found) {
                    totalFee += newTransmittersFee;
                }
                unchecked {
                    ++i;
                }
            }
            delete i;
            if (totalFee > 0) {
                if (
                    !(checkProtocolBalance(_protocolId) &&
                        protocolInfo[_protocolId].balance >= totalFee)
                ) {
                    revert ExternalDeveloperHub__InsufficientFunds();
                }
                protocolInfo[_protocolId].balance -= totalFee;
                stakingManager.creditSystemFee(totalFee);
            }
        }

        protocolInfo[_protocolId].manualTransmitters = _transmitters;
        requireParamsValid(_protocolId);
        emit SetManualTransmitters(_protocolId, _transmitters);
    }

    /// @notice Set protocol contract address
    /// @param _protocolId - Protocol id
    /// @param _chainId - Chain id
    /// @param _protocolAddress - Protocol address
    function addAllowedProtocolAddress(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _protocolAddress
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        if (_protocolAddress.length == 0) {
            revert ExternalDeveloperHub__ZeroAddress();
        }
        if (_protocolAddress.length > OperationLib.ADDRESS_MAX_LEN) {
            revert ExternalDeveloperHub__AddrTooBig(_protocolId);
        }
        masterSmartContract.addAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
        deduceChangeParamsFee(_protocolId);
        if (
            !masterSmartContract.isInited(_protocolId, _chainId) &&
            globalConfig.initNewChainFee() > 0 &&
            _protocolId != masterSmartContract.govProtocolId()
        ) {
            uint totalFee = globalConfig.initNewChainFee();
            if (totalFee > 0) {
                if (
                    !(checkProtocolBalance(_protocolId) &&
                        protocolInfo[_protocolId].balance >= totalFee)
                ) {
                    revert ExternalDeveloperHub__InsufficientFunds();
                }
                protocolInfo[_protocolId].balance -= totalFee;
                stakingManager.creditSystemFee(totalFee);
            }
        }
        requireParamsValid(_protocolId);
        emit AddAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
    }

    /// @notice Remove protocol contract address
    /// @param _protocolId - Protocol id
    /// @param _chainId - Chain id
    /// @param _protocolAddress - Protocol address
    function removeAllowedProtocolAddress(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _protocolAddress
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        masterSmartContract.removeAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
        deduceChangeParamsFee(_protocolId);
        requireParamsValid(_protocolId);
        emit RemoveAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
    }

    /// @notice Set address that can propose new operations on EndPoint
    /// @param _protocolId - Protocol id
    /// @param _proposerAddress - Address that can propose new operations
    function addAllowedProposerAddress(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _proposerAddress
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        if (_proposerAddress.length == 0) {
            revert ExternalDeveloperHub__ZeroAddress();
        }
        if (_proposerAddress.length > OperationLib.ADDRESS_MAX_LEN) {
            revert ExternalDeveloperHub__AddrTooBig(_protocolId);
        }
        masterSmartContract.addAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
        deduceChangeParamsFee(_protocolId);
        requireParamsValid(_protocolId);
        emit AddAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
    }

    /// @notice Remove address that can propose new operations on EndPoint
    /// @param _protocolId - Protocol id
    /// @param _chainId - Chain id
    /// @param _proposerAddress - Address that can propose new operations
    function removeAllowedProposerAddress(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _proposerAddress
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        masterSmartContract.removeAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
        deduceChangeParamsFee(_protocolId);
        requireParamsValid(_protocolId);
        emit RemoveAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
    }

    /// @notice Add executor address (which can call executeOperation on EndPoint with protocols operations)
    /// @param _protocolId - Protocol id
    /// @param _chainId - Chain id
    /// @param _executor - Executor address
    function addExecutor(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _executor
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        if (_executor.length == 0) {
            revert ExternalDeveloperHub__ZeroAddress();
        }
        if (_executor.length > OperationLib.ADDRESS_MAX_LEN) {
            revert ExternalDeveloperHub__AddrTooBig(_protocolId);
        }
        if (_protocolId == masterSmartContract.govProtocolId()) {
            govExecutors[_chainId]++;
        }
        masterSmartContract.addExecutor(_protocolId, _chainId, _executor);
        deduceChangeParamsFee(_protocolId);
        requireParamsValid(_protocolId);
        emit AddExecutor(_protocolId, _chainId, _executor);
    }

    /// @notice Remove executor address
    /// @param _protocolId - Protocol id
    /// @param _chainId - Chain id
    /// @param _executor - Executor address
    function removeExecutor(
        bytes32 _protocolId,
        uint _chainId,
        bytes calldata _executor
    ) external protocolOwner(_protocolId) allowedChainId(_chainId) {
        if (_protocolId == masterSmartContract.govProtocolId()) {
            if (govExecutors[_chainId] <= 1) {
                revert ExternalDeveloperHub__ZeroGovExecutors(_protocolId, _chainId);
            }
            govExecutors[_chainId]--;
        }
        masterSmartContract.removeExecutor(_protocolId, _chainId, _executor);
        deduceChangeParamsFee(_protocolId);
        requireParamsValid(_protocolId);
        emit RemoveExecutor(_protocolId, _chainId, _executor);
    }

    /// @notice Claim unlocked balance
    function claimBalance() nonReentrant external {
        if (unlockedBalance[_msgSender()] == 0) {
            revert ExternalDeveloperHub__NothingToClaim();
        }
        stakingManager.transferTo(_msgSender(), unlockedBalance[_msgSender()]);
        unlockedBalance[_msgSender()] = 0;
    }

    /// @notice Activate or deactivate protocol
    /// @param _protocolId - Protocol id
    /// @param _active - true: activate protocol, false: deactivate protocol
    function setActive(bytes32 _protocolId, bool _active) external protocolOwner(_protocolId) {
        protocolInfo[_protocolId].active = _active;
    }

    /// @notice Minimum delegate amount for transmitters that can participate in protocol
    /// @param _protocolId - Protocol id
    function minDelegateAmount(bytes32 _protocolId) external view returns (uint) {
        return protocolInfo[_protocolId].minDelegateAmount;
    }

    /// @notice Minimum personal stake amount for transmitters that can participate in protocol
    /// @param _protocolId - Protocol id
    function minPersonalAmount(bytes32 _protocolId) external view returns (uint) {
        return protocolInfo[_protocolId].minPersonalAmount;
    }

    /// @notice Maximum number of transmitters that can participate in protocol
    /// @param _protocolId - Protocol id
    function maxTransmitters(bytes32 _protocolId) external view returns (uint) {
        return protocolInfo[_protocolId].maxTransmitters;
    }

    /// @notice Protocol fee deduced from protocol balance on each operation
    /// @param _protocolId - Protocol id
    function protocolFee(bytes32 _protocolId) external view returns (uint) {
        return protocolInfo[_protocolId].fee;
    }

    /// @notice Get protocol min balance
    /// @param _protocolId - Protocol id
    function getMinProtocolBalance(bytes32 _protocolId) public view returns (uint) {
        return
            minProtocolBalance[_protocolId] > 0
                ? minProtocolBalance[_protocolId]
                : globalConfig.minProtocolBalance();
    }

    /// @notice Check if protocol balance is above minimum of (global minProtocolBalance or protocol specific min balance)
    /// @param _protocolId Protocol id
    /// @return bool True if protocol balance is above minimum
    function checkProtocolBalance(bytes32 _protocolId) internal view returns (bool) {
        if (_protocolId == masterSmartContract.govProtocolId()) {
            return true;
        }
        return
            minProtocolBalance[_protocolId] > 0
                ? protocolInfo[_protocolId].balance >= minProtocolBalance[_protocolId]
                : protocolInfo[_protocolId].balance >= globalConfig.minProtocolBalance();
    }

    /// @notice Get required bet amount for protocol for given bet type
    /// @param _protocolId - Protocol id
    /// @param betType - BetType (Message or Data)
    function betAmount(
        bytes32 _protocolId,
        BetManager.BetType betType
    ) external view returns (uint) {
        if (betType == BetManager.BetType.Msg) {
            return activeParams[_protocolId].msgBetAmount;
        } else {
            return activeParams[_protocolId].dataBetAmount;
        }
    }

    /// @notice Get reward amount credited to each participating transmitter after operation is executed
    /// @param _protocolId - Protocol id
    /// @param betType - BetType (Message or Data)
    /// @param first - First bet
    function rewardAmount(
        bytes32 _protocolId,
        BetManager.BetType betType,
        bool first
    ) external view returns (uint) {
        if (betType == BetManager.BetType.Msg) {
            if (first) {
                return activeParams[_protocolId].msgBetFirstReward;
            }
            return activeParams[_protocolId].msgBetReward;
        } else {
            if (first) {
                return activeParams[_protocolId].dataBetFirstReward;
            }
            return activeParams[_protocolId].dataBetReward;
        }
    }

    /// @notice Get protocol owner
    /// @param _protocolId - Protocol id
    function getProtocolOwner(bytes32 _protocolId) external view returns (address) {
        return protocolInfo[_protocolId].owner;
    }

    /// @notice Get current protocol balance
    /// @param protocolId - Protocol id
    function protocolBalance(bytes32 protocolId) external view returns (uint) {
        return protocolInfo[protocolId].balance;
    }

    /// @notice Get list of transmitters added by externalDeveloper
    /// @param protocolId - Protocol id
    function manualTransmitters(bytes32 protocolId) external view returns (address[] memory) {
        return protocolInfo[protocolId].manualTransmitters;
    }

    /// @notice Check if transmitter is static and added by externalDeveloper
    /// @param protocolId - Protocol id
    /// @param transmitter - Transmitter address
    function isManualTransmitter(
        bytes32 protocolId,
        address transmitter
    ) external view returns (bool) {
        uint n = protocolInfo[protocolId].manualTransmitters.length;
        for (uint i; i < n; ) {
            if (protocolInfo[protocolId].manualTransmitters[i] == transmitter) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Get protocol list
    function getProtocols() external view returns (bytes32[] memory) {
        return protocols;
    }

    /// @notice Update active params from realtime params for each protocol
    function turnRound() external onlyRole(ROUND_MANAGER) {
        uint n = protocols.length;
        bytes32 govProtocolId = masterSmartContract.govProtocolId();
        for (uint i; i < n; ) {
            if (
                activeParams[protocols[i]].consensusTargetRate !=
                realtimeParams[protocols[i]].consensusTargetRate
            ) {
                masterSmartContract.setConsensusTargetRate(
                    protocols[i],
                    realtimeParams[protocols[i]].consensusTargetRate
                );
            }
            activeParams[protocols[i]] = realtimeParams[protocols[i]];
            ProtocolInfo storage _protocolInfo = protocolInfo[protocols[i]];
            if (
                protocols[i] != govProtocolId &&
                (!checkProtocolBalance(protocols[i]) || !_protocolInfo.active) &&
                !masterSmartContract.isPaused(protocols[i])
            ) {
                masterSmartContract.setProtocolPause(protocols[i], true);
            }
            if (!_protocolInfo.active) {
                if (_protocolInfo.balance > 0) {
                    unlockedBalance[_protocolInfo.owner] += _protocolInfo.balance;
                    _protocolInfo.balance = 0;
                }
                if (masterSmartContract.numberOfAllowedTransmitters(protocols[i]) > 0) {
                    masterSmartContract.updateTransmitters(protocols[i], new address[](0));
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Either deduce fee or pause protocol if no funds left
    /// @param _protocolId - Protocol id
    /// @param _amount - Amount of NGL to deduce
    function deduceFee(
        bytes32 _protocolId,
        uint _amount
    ) external onlyRole(BET_MANAGER) returns (bool) {
        if (protocolInfo[_protocolId].owner == address(0)) {
            revert ExternalDeveloperHub__ProtocolNotRegistered(_protocolId);
        }
        if (!checkProtocolBalance(_protocolId)) {
            masterSmartContract.setProtocolPause(_protocolId, true);
        }
        if (protocolInfo[_protocolId].balance > _amount) {
            protocolInfo[_protocolId].balance -= _amount;
            return true;
        } else {
            masterSmartContract.setProtocolPause(_protocolId, true);
            return false;
        }
    }
}
