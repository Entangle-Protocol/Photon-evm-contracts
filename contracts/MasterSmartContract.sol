//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./MSCProposeHelper.sol";
import "./IProposer.sol";
import "./staking/BetManager.sol";
import "./staking/ExternalDeveloperHub.sol";
import "./lib/OperationLib.sol";
import "./staking/StakingManager.sol";
import "./lib/ArrayLib.sol";
import "./lib/PhotonOperationMetaLib.sol";

/// @notice Master Smart Contract is a contract which should collect operations from transmitters with those signatures.
/// Also it has gov functions which can administrate protocols:
/// - allow new protocol
/// - add/remove protocol address to interact on specified chain
/// - add/remove proposer address on specified chain wich can proposing new operations due EndPoint.propose() function.
/// - update transmitters on protocol
/// - add/remove executors on specified chain
/// - set consensus target rate
contract MasterSmartContract is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    error MasterSmartContract__GovProtocolAlreadyInited();
    error MasterSmartContract__GovProtocolIsNotInited();
    error MasterSmartContract__InvalidProtocolId(bytes32);
    error MasterSmartContract__ForbiddenOperationWithGovProtocol();
    error MasterSmartContract__DaoIsNotAllowedOnSpecifiedChain(uint256);
    error MasterSmartContract__ProtocolIsNotInited(bytes32);
    error MasterSmartContract__ProtocolIsNotInitedOnChain(bytes32, uint256);
    error MasterSmartContract__ProtocolAlreadyAdded(bytes32);
    error MasterSmartContract__ProtocolIsNotAllowed(bytes32);
    error MasterSmartContract__ProtocolAddressAlreadyExist(bytes32, bytes);
    error MasterSmartContract__TransmitterIsAlreadyAdded(bytes32, address);
    error MasterSmartContract__TransmitterIsNotAllowed(bytes32, address);
    error MasterSmartContract__WatcherIsNotAllowed(address);
    error MasterSmartContract__OperationIsAlreadyApproved(uint256);
    error MasterSmartContract__TransmitterIsAlreadyApproved(address, uint256);
    error MasterSmartContract__WatcherIsAlreadyApproved(address, uint256);
    error MasterSmartContract__OperationDoesNotExist(uint256);
    error MasterSmartContract__OpIsNotApproved(uint256);
    error MasterSmartContract__OpExecutionAlreadyApproved(uint256);
    error MasterSmartContract__SignatureCheckFailed(uint256, address);
    error MasterSmartContract__ProtocolIsPaused(bytes32);
    error MasterSmartContract__AddrTooBig(bytes32);
    error MasterSmartContract__SelectorTooBig(bytes32);
    error MasterSmartContract__ParamsTooBig(bytes32);
    error MasterSmartContract__InvalidChainId(uint256);

    /*** EVENTS FOR BACKEND ***/
    // Admin functionality
    event AddAllowedProtocol(bytes32 indexed protocolId, uint256 consensusTargetRate);
    event SetProtocolPause(bytes32 indexed protocolId, bool state);
    // Protocol owner's functionality
    event AddAllowedProtocolAddress(bytes32 indexed protocolId, uint256 chainId, bytes protocolAddress);
    event RemoveAllowedProtocolAddress(bytes32 indexed protocolId, uint256 chainId, bytes protocolAddress);
    event AddAllowedProposerAddress(bytes32 indexed protocolId, uint256 chainId, bytes proposerAddress);
    event RemoveAllowedProposerAddress(bytes32 indexed protocolId, uint256 chainId, bytes proposerAddress);
    event UpdateTransmitters(bytes32 indexed protocolId, address[] toAdd, address[] toRemove);
    event RemoveTransmitter(bytes32 indexed protocolId, address transmitter);
    event AddExecutor(bytes32 indexed protocolId, uint256 chainId, bytes executor);
    event RemoveExecutor(bytes32 indexed protocolId, uint256 chainId, bytes executor);
    event SetConsensusTargetRate(bytes32 indexed protocolId, uint256 rate);
    /*** END OF EVENTS FOR BACKEND ***/

    event NewOperation(bytes32 indexed protocolId, uint256 opHash, uint256 meta, address transmitter);
    event NewProof(bytes32 indexed protocolId, uint256 opHash, address transmitter);
    event ProposalApproved(bytes32 indexed protocolId, uint256 opHash);
    event ProposalExecuted(bytes32 indexed protocolId, uint256 opHash);

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant ENDPOINT = keccak256("ENDPOINT");
    bytes32 public constant STAKING_CONTRACTS = keccak256("STAKING_CONTRACTS");

    enum InitOnChainStages {
        NotInited,
        OnInition,
        Inited
    }

    /// @notice struct for collecting pending admin protocol operations wich on inition stage
    /// @param stage operation stage: not inited, on initions, inited
    /// @param queuedProtocolAddresses array of protocol addresses which should be added on endPoint when protocol become inited on chain
    /// @param queuedProposerAddresses array of proposer addresses which should be added on endPoint when protocol become inited on chain
    /// @param queuedTransmitters array of transmitters which should be added on endPoint when protocol become inited on chain
    struct InitOnChainInfo {
        InitOnChainStages stage;
        bytes[] queuedProtocolAddresses;
        bytes[] queuedProposerAddresses;
        address[] queuedTransmitters;
    }

    /// @notice struct with allowed protocol info
    /// @param isInit indicates if protocol inited
    /// @param isPaused indicates if protocol work paused
    /// @param consensusTargetRate percentage of proofs div numberOfAllowedTransmitters which should be reached to approve operation. Scaled with 10000 decimals, e.g. 6000 is 60%
    /// @param chainIds array of chains where protocol works
    /// @param transmitters set of transmitters which can work with this protocol
    /// @param initOnChainInfo init stage on chainId
    struct AllowedProtocolInfo {
        bool isInit;
        bool isPaused;
        uint256 consensusTargetRate;
        uint256[] chainIds;
        EnumerableSet.AddressSet transmitters;
        mapping(uint256 chainId => InitOnChainInfo) initOnChainInfo;
    }

    /// @notice Structure for information that holds knowledge of operation status
    /// @param isApproved Indicates if the operation is approved and ready to execute
    /// @param isExecuted Indicates if the operation has been executed
    /// @param proofsCount The number of proofs by unique transmitters
    /// @param watchersProofCount The number of watchers which approve the operation as executed
    /// @param round The round number of the operation
    /// @param approveBlockNumber The block number when the operation was approved
    /// @param proofedTransmitters An array of transmitters who have provided proofs of the operation
    /// @param proofedWatchers An array of watchers who have confirmed the execution of the operation
    /// @param transmitterSigs An array of signatures of the operation from transmitters
    struct ProofInfo {
        bool isApproved;
        bool isExecuted;
        uint32 proofsCount;
        uint32 watchersProofCount;
        uint256 round;
        uint256 approveBlockNumber;
        address[] proofedTransmitters;
        address[] proofedWatchers;
        OperationLib.Signature[] transmitterSigs;
    }

    /// @notice Main structure that keeps all information about an operation
    /// @param proofInfo Information about the status of the operation
    /// @param operationData Information about the operation calling process
    struct Operation {
        ProofInfo proofInfo;
        OperationLib.OperationData operationData;
    }

    bool isInit;
    /// @notice allowedExecutors map of allowed executors addresses which can execute operations on specified protocol on specified chain
    mapping(bytes32 protoId => mapping(uint256 chainId => mapping(bytes addr => bool))) public
        allowedExecutors;
    /// @notice allowedProposers map of allowed proposers addresses which can propose operations on specified protocol on specified chain
    mapping(bytes32 protoId => mapping(uint256 chainId => mapping(bytes addr => bool))) public
        allowedProposers;

    /// @notice map with operations, key: opHash is a uint256(keccak256(OperationData operationData)), value - Operation which need to validate and execute
    mapping(uint256 opHash => Operation operation) operations;

    /// @notice map with allowed protocols info
    mapping(bytes32 protoId => AllowedProtocolInfo info) allowedProtocolInfo;
    /// @notice map to associate specified protocol contract on specified chain id with protocol id
    mapping(uint256 chainId => mapping(bytes protoAddress => bytes32 protoId)) public protocolAddressToProtocolId;

    /// @notice 10000 = 100%
    uint256 constant rateDecimals = 10000;

    /// @notice watcher wich should approve operation execution
    mapping(address => bool) public allowedWatchers;
    /// @notice number of allowed watchers
    uint256 public numberOfAllowedWatchers;
    /// @notice watchers consensus target rate
    uint256 public watchersConsensusTargetRate;

    /// @notice proposer contract
    IProposer endPoint;

    /// @notice transmitters bet manager
    BetManager betManager;

    /// @notice staking manager
    StakingManager stakingManager;

    /// @notice propose helper
    MSCProposeHelper proposeHelper;

    /// @notice last executed ordered operation nonce for specified protocol on specified chain
    /// @dev used for ordered operations to notify executors about last executed operation nonce
    mapping(bytes32 protocolId => mapping(uint256 srcChainId => uint)) public
        lastExecutedOpNonceInOrder;

    /** END of VARS **/

    modifier onlyAllowedTransmitter(bytes32 _protocolId) {
        if (!isAllowedTransmitter(_protocolId, _msgSender())) {
            revert MasterSmartContract__TransmitterIsNotAllowed(_protocolId, _msgSender());
        }
        _;
    }

    modifier onlyAllowedWatcher() {
        if (!allowedWatchers[_msgSender()]) {
            revert MasterSmartContract__WatcherIsNotAllowed(_msgSender());
        }
        _;
    }

    modifier onlyAllowedProtocol(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _protocolAddr
    ) {
        if (!allowedProtocolInfo[_protocolId].isInit) {
            revert MasterSmartContract__ProtocolIsNotInited(_protocolId);
        }
        if (protocolAddressToProtocolId[_chainId][_protocolAddr] != _protocolId) {
            revert MasterSmartContract__ProtocolIsNotAllowed(_protocolId);
        }
        _;
    }

    function __chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    function govProtocolId() public view returns (bytes32) {
        return proposeHelper.govProtocolId();
    }

    /// @notice Initialize
    /// @param initAddr[0] - Admin address
    /// @param initAddr[1] - EndPoint address
    function initialize(address[2] calldata initAddr) external initializer {
        __UUPSUpgradeable_init();
        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        endPoint = IProposer(initAddr[1]);
        _grantRole(ENDPOINT, initAddr[1]);
        watchersConsensusTargetRate = 6000;
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    /// @notice Set contracts addresses
    /// @param initAddr[0] - externalDeveloperHub
    /// @param initAddr[1] - roundManager
    /// @param initAddr[2] - betManager
    /// @param initAddr[3] - agentManager
    /// @param initAddr[4] - stakingManager
    /// @param initAddr[5] - proposeHelper
    function setContracts(address[6] calldata initAddr) external onlyRole(ADMIN) {
        require(!isInit);
        isInit = true;
        _grantRole(STAKING_CONTRACTS, initAddr[0]); // externalDeveloperHub
        _grantRole(STAKING_CONTRACTS, initAddr[1]); // roundManager
        betManager = BetManager(initAddr[2]);
        _grantRole(STAKING_CONTRACTS, address(betManager));
        _grantRole(STAKING_CONTRACTS, initAddr[3]); // agentManager
        _grantRole(STAKING_CONTRACTS, initAddr[4]); // stakingManager
        stakingManager = StakingManager(initAddr[4]);
        proposeHelper = MSCProposeHelper(initAddr[5]);
    }

    /*** CALLBACK FUNTIONS ***/
    /// @notice Callback function for handle 2nd step of protocol inition on specified chain.
    /// @dev called by EndPoint from specified chain, after addAllowedProtocol processing
    /// @param _params encoded params
    function handleAddAllowedProtocol(bytes calldata _params) external onlyRole(ENDPOINT) {
        (bytes32 _govProtocolId, , , , bytes memory params) = abi.decode(
            _params,
            (bytes32, uint256, uint256, bytes32[2], bytes)
        );
        require(_govProtocolId == govProtocolId());
        (bytes32 protocolId, uint256 chainId) = abi.decode(params, (bytes32, uint256));
        allowedProtocolInfo[protocolId].initOnChainInfo[chainId].stage = InitOnChainStages.Inited;
        InitOnChainInfo memory info = allowedProtocolInfo[protocolId].initOnChainInfo[chainId];
        uint len = info.queuedProtocolAddresses.length;
        uint i;
        while (i < len) {
            proposeHelper.proposeAddAllowedProtocolAddress(protocolId, chainId, info.queuedProtocolAddresses[i]);
            unchecked {
                ++i;
            }
        }
        delete allowedProtocolInfo[protocolId].initOnChainInfo[chainId].queuedProtocolAddresses;

        len = info.queuedProposerAddresses.length;

        delete i;
        while (i < len) {
            proposeHelper.proposeAddAllowedProposerAddress(protocolId, chainId, info.queuedProposerAddresses[i]);
            unchecked {
                ++i;
            }
        }
        delete allowedProtocolInfo[protocolId].initOnChainInfo[chainId].queuedProposerAddresses;

        len = info.queuedTransmitters.length;
        if (len > 0) {
            address[] memory transmittersToPropose = new address[](len);
            uint n;

            delete i;
            for (; i < len; ) {
                address transmitter = info.queuedTransmitters[i];
                // transmitter can be removed after adding when chain on inition and instantly removed (low probability, but Murphy's law)
                if (isAllowedTransmitter(protocolId, transmitter)) {
                    transmittersToPropose[n] = transmitter;
                    unchecked {
                        ++n;
                    }
                }
                unchecked {
                    ++i;
                }
            }

            assembly {
                mstore(transmittersToPropose, n)
            }

            if (transmittersToPropose.length != 0) {
                proposeHelper.proposeAddTransmitters(protocolId, chainId, transmittersToPropose);
            }
            delete allowedProtocolInfo[protocolId].initOnChainInfo[chainId].queuedTransmitters;
        }
    }

    /*** ADMIN FUNCTIONS ***/

    /// @notice Adding info about GOV protocol
    /// @param _consensusTargetRate rate with 10000 decimals
    /// @param _transmitters array of initial gov transmitters
    function initGovProtocol(
        uint256 _consensusTargetRate,
        address[] calldata _transmitters
    ) external onlyRole(STAKING_CONTRACTS) {
        if (allowedProtocolInfo[govProtocolId()].isInit)
            revert MasterSmartContract__GovProtocolAlreadyInited();
        allowedProtocolInfo[govProtocolId()].isInit = true;
        allowedProtocolInfo[govProtocolId()].consensusTargetRate = _consensusTargetRate;
        for (uint i; i < _transmitters.length; ) {
            if (allowedProtocolInfo[govProtocolId()].transmitters.add(_transmitters[i])) {
                addWatcher(_transmitters[i]);
            }
            unchecked {
                ++i;
            }
        }
        // add propose helper as allowed proposer in gov protocol
        allowedProposers[govProtocolId()][__chainId()][abi.encode(address(proposeHelper))] = true;
        // add msc as allowed protocol (target) contract in gov protocol
        protocolAddressToProtocolId[__chainId()][abi.encode(address(this))] = govProtocolId();
    }

    /// @notice add gov contract address and executors on specified chain
    /// @param _chainId chain id
    /// @param _govAddress address of gov contract on specified chain
    /// @param _executors address of executors which will be execute operations on specified chain
    function addGovProtocolAddress(
        uint256 _chainId,
        bytes calldata _govAddress,
        bytes[] calldata _executors
    ) external onlyRole(STAKING_CONTRACTS) {
        if (!allowedProtocolInfo[govProtocolId()].isInit)
            revert MasterSmartContract__GovProtocolIsNotInited();
        uint l = allowedProtocolInfo[govProtocolId()].chainIds.length;
        bool isNewChainId = true;
        uint i;
        while (i < l) {
            if (allowedProtocolInfo[govProtocolId()].chainIds[i] == _chainId) {
                isNewChainId = false;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (isNewChainId) {
            allowedProtocolInfo[govProtocolId()].chainIds.push(_chainId);
        }
        delete i;
        while (i < _executors.length) {
            allowedExecutors[govProtocolId()][_chainId][_executors[i]] = true;
            unchecked {
                ++i;
            }
        }
        allowedProtocolInfo[govProtocolId()].initOnChainInfo[_chainId].stage = InitOnChainStages
            .Inited;
        proposeHelper.setGovContractAddress(_chainId, _govAddress);
        protocolAddressToProtocolId[_chainId][_govAddress] = govProtocolId();
    }

    /// @notice Adding new protocol by id
    /// @param _protocolId protocol Id (may be proto short name or number)
    /// @param _consensusTargetRate rate with 10000 decimals
    function addProtocol(
        bytes32 _protocolId,
        uint256 _consensusTargetRate
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == bytes32(0)) revert MasterSmartContract__InvalidProtocolId(_protocolId);
        if (allowedProtocolInfo[_protocolId].isInit)
            revert MasterSmartContract__ProtocolAlreadyAdded(_protocolId);
        allowedProtocolInfo[_protocolId].isInit = true;
        allowedProtocolInfo[_protocolId].consensusTargetRate = _consensusTargetRate;
        emit AddAllowedProtocol(_protocolId, _consensusTargetRate);
    }

    /// @notice Pause/unpause protocol
    /// @param _protocolId protocol id
    /// @param _state true - pause, false - unpause
    function setProtocolPause(
        bytes32 _protocolId,
        bool _state
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == bytes32(0)) revert MasterSmartContract__InvalidProtocolId(_protocolId);
        if (!allowedProtocolInfo[_protocolId].isInit)
            revert MasterSmartContract__ProtocolIsNotInited(_protocolId);
        if (_protocolId == govProtocolId())
            revert MasterSmartContract__ForbiddenOperationWithGovProtocol();
        allowedProtocolInfo[_protocolId].isPaused = _state;
        emit SetProtocolPause(_protocolId, _state);
    }

    /// @notice Adding watcher to whitelist
    /// @param _watcher address of watcher to add
    function addWatcher(address _watcher) internal {
        if (!allowedWatchers[_watcher]) {
            allowedWatchers[_watcher] = true;
            ++numberOfAllowedWatchers;
        }
    }

    /// @notice Removing watcher from whitelist
    /// @param _watcher address of watcher to remove
    function removeWatcher(address _watcher) internal {
        if (allowedWatchers[_watcher]) {
            allowedWatchers[_watcher] = false;
            --numberOfAllowedWatchers;
        }
    }

    /// @notice Removing watcher from whitelist
    /// @param _rate rate
    function setWatchersConsensusTargetRate(uint256 _rate) external onlyRole(ADMIN) {
        require(_rate <= rateDecimals && _rate > 5500);
        watchersConsensusTargetRate = _rate;
    }

    /*** PROTOCOL OWNER FUNCTIONS ***/

    /// @notice Adding chainId and protocol address to whitelist
    /// @param _protocolId protocol id
    /// @param _chainId chainId of this address of protocol contract
    /// @param _protocolAddress protocol address of contract
    function addAllowedProtocolAddress(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _protocolAddress
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == govProtocolId())
            revert MasterSmartContract__ForbiddenOperationWithGovProtocol();

        bytes32 _findedProtocolId = protocolAddressToProtocolId[_chainId][_protocolAddress];
        if (_findedProtocolId != bytes32(0))
            revert MasterSmartContract__ProtocolAddressAlreadyExist(
                _findedProtocolId,
                _protocolAddress
            );

        uint l = allowedProtocolInfo[_protocolId].chainIds.length;
        bool isNewChainId = true;
        for (uint i; i < l; ) {
            if (allowedProtocolInfo[_protocolId].chainIds[i] == _chainId) {
                isNewChainId = false;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (isNewChainId) {
            allowedProtocolInfo[_protocolId].chainIds.push(_chainId);
        }
        protocolAddressToProtocolId[_chainId][_protocolAddress] = _protocolId;
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.NotInited
        ) {
            // add protocol address in queue
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].queuedProtocolAddresses.push(
                    _protocolAddress
                );
            // init protocol in endPoint on specified chain
            address[] memory transmittersArr = allowedProtocolInfo[_protocolId]
                .transmitters
                .values();

            proposeHelper.proposeAddAllowedProtocol(
                _protocolId,
                _chainId,
                allowedProtocolInfo[_protocolId].consensusTargetRate,
                transmittersArr
            );
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage = InitOnChainStages
                .OnInition;
        } else if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.OnInition
        ) {
            // add protocol address in queue
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].queuedProtocolAddresses.push(
                    _protocolAddress
                );
        } else if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.Inited
        ) {
            // just add new protocol address
            proposeHelper.proposeAddAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
        }
        emit AddAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
    }

    /// @notice Removing  protocol address from whitelist for specified protocol on specified chain
    /// @param _protocolId protocol id
    /// @param _chainId chain id
    /// @param _protocolAddress protocol address to remove
    function removeAllowedProtocolAddress(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _protocolAddress
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == govProtocolId())
            revert MasterSmartContract__ForbiddenOperationWithGovProtocol();
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage !=
            InitOnChainStages.Inited
        ) revert MasterSmartContract__ProtocolIsNotInitedOnChain(_protocolId, _chainId);
        protocolAddressToProtocolId[_chainId][_protocolAddress] = bytes32(0);
        proposeHelper.proposeRemoveAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
        emit RemoveAllowedProtocolAddress(_protocolId, _chainId, _protocolAddress);
    }

    /// @notice Adding proposer to whitelist for specified protocol on specified chain
    /// @param _protocolId protocol id
    /// @param _chainId chain id
    /// @param _proposerAddress proposer address to add
    function addAllowedProposerAddress(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _proposerAddress
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == govProtocolId())
            revert MasterSmartContract__ForbiddenOperationWithGovProtocol();
        allowedProposers[_protocolId][_chainId][_proposerAddress] = true;
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.NotInited
        ) {
            // add proposer address in queue
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].queuedProposerAddresses.push(
                    _proposerAddress
                );
            // init protocol in endPoint on specified chain
            address[] memory transmittersArr = allowedProtocolInfo[_protocolId]
                .transmitters
                .values();

            proposeHelper.proposeAddAllowedProtocol(
                _protocolId,
                _chainId,
                allowedProtocolInfo[_protocolId].consensusTargetRate,
                transmittersArr
            );
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage = InitOnChainStages
                .OnInition;
        } else if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.OnInition
        ) {
            // add proposer address in queue
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].queuedProposerAddresses.push(
                    _proposerAddress
                );
        } else if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage ==
            InitOnChainStages.Inited
        ) {
            // just add new proposer address
            proposeHelper.proposeAddAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
        }
        emit AddAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
    }

    /// @notice Removing proposer from whitelist for specified protocol on specified chain
    /// @param _protocolId protocol id
    /// @param _chainId chain id
    /// @param _proposerAddress proposer address to remove
    function removeAllowedProposerAddress(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _proposerAddress
    ) external onlyRole(STAKING_CONTRACTS) {
        if (_protocolId == govProtocolId())
            revert MasterSmartContract__ForbiddenOperationWithGovProtocol();
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage !=
            InitOnChainStages.Inited
        ) revert MasterSmartContract__ProtocolIsNotInitedOnChain(_protocolId, _chainId);
        allowedProposers[_protocolId][_chainId][_proposerAddress] = false;
        proposeHelper.proposeRemoveAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
        emit RemoveAllowedProposerAddress(_protocolId, _chainId, _proposerAddress);
    }

    /// @notice Adding executor to specified protocol on specified chain id
    /// @param _protocolId protocol id
    /// @param _chainId target chain id
    /// @param _executor executor address or pubkey
    function addExecutor(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _executor
    ) external onlyRole(STAKING_CONTRACTS) {
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage !=
            InitOnChainStages.Inited
        ) revert MasterSmartContract__ProtocolIsNotInitedOnChain(_protocolId, _chainId);
        allowedExecutors[_protocolId][_chainId][_executor] = true;
        proposeHelper.proposeAddExecutor(_protocolId, _chainId, _executor);
        emit AddExecutor(_protocolId, _chainId, _executor);
    }

    /// @notice Removing executor to specified protocol on specified chain id
    /// @param _protocolId protocol id
    /// @param _chainId target chain id
    /// @param _executor executor address or pubkey
    function removeExecutor(
        bytes32 _protocolId,
        uint256 _chainId,
        bytes calldata _executor
    ) external onlyRole(STAKING_CONTRACTS) {
        if (
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage !=
            InitOnChainStages.Inited
        ) revert MasterSmartContract__ProtocolIsNotInitedOnChain(_protocolId, _chainId);
        allowedExecutors[_protocolId][_chainId][_executor] = false;
        proposeHelper.proposeRemoveExecutor(_protocolId, _chainId, _executor);
        emit RemoveExecutor(_protocolId, _chainId, _executor);
    }

    /// @notice Update transmitters to specified protocol
    /// @dev called by RoundManager and AgentManager
    /// @param _protocolId protocol id
    /// @param newTransmittersArr new selected transmitter's array
    function updateTransmitters(
        bytes32 _protocolId,
        address[] calldata newTransmittersArr
    ) external onlyRole(STAKING_CONTRACTS) {
        EnumerableSet.AddressSet storage currentTransmitters = allowedProtocolInfo[_protocolId]
            .transmitters;
        uint i;
        // Check if current and new transmitters are the same
        if (newTransmittersArr.length == currentTransmitters.length()) {
            bool diff;
            while (i < newTransmittersArr.length) {
                if (!currentTransmitters.contains(newTransmittersArr[i])) {
                    diff = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            if (!diff) {
                return;
            }
            delete i;
        }
        // Calculate toAdd
        uint newTransmittersLength = newTransmittersArr.length;
        address[] memory toAdd = new address[](newTransmittersLength);
        uint n;
        address t;
        delete i;
        while (i < newTransmittersLength) {
            t = newTransmittersArr[i];
            if (currentTransmitters.add(t)) {
                toAdd[n++] = t;
                addWatcher(t);
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(toAdd, n)
        }
        // Calculate toRemove
        address[] memory toRemove = new address[](currentTransmitters.length());
        delete n;
        delete i;
        address[] memory currentTransmittersArr = currentTransmitters.values();
        while (i < currentTransmittersArr.length) {
            t = currentTransmittersArr[i];
            if (!ArrayLib.containsAddress(newTransmittersArr, t)) {
                toRemove[n++] = t;
                removeWatcher(t);
                currentTransmitters.remove(t);
            }
            unchecked {
                ++i;
            }
        }
        assembly {
            mstore(toRemove, n)
        }
        // Broadcast transmitters
        AllowedProtocolInfo storage info = allowedProtocolInfo[_protocolId];
        n = info.chainIds.length;
        bool toQueueInited;
        address[] memory toQueue;
        delete i;
        while (i < n) {
            uint chainId = info.chainIds[i];
            if (info.initOnChainInfo[chainId].stage == InitOnChainStages.Inited) {
                if (toAdd.length > 0 && toRemove.length == 0) {
                    proposeHelper.proposeAddTransmitters(_protocolId, chainId, toAdd);
                } else if (toAdd.length == 0 && toRemove.length > 0) {
                    proposeHelper.proposeRemoveTransmitters(_protocolId, chainId, toRemove);
                } else if (toAdd.length > 0 && toRemove.length > 0) {
                    proposeHelper.proposeUpdateTransmitters(_protocolId, chainId, toAdd, toRemove);
                }
            } else if (info.initOnChainInfo[chainId].stage == InitOnChainStages.OnInition) {
                if (!toQueueInited) {
                    uint currentTransmittersLength = currentTransmitters.length();
                    toQueue = new address[](currentTransmittersLength);
                    uint j;
                    while (j < currentTransmittersLength) {
                        toQueue[i] = currentTransmitters.at(j);
                        unchecked {
                            ++j;
                        }
                    }
                    toQueueInited = true;
                }
                info.initOnChainInfo[chainId].queuedTransmitters = toQueue;
            }
            unchecked {
                ++i;
            }
        }
        emit UpdateTransmitters(_protocolId, toAdd, toRemove);
    }

    /// @notice Removing transmitters from whitelist
    /// @notice called when transmitters was banned or slashed
    /// @param _protocolId protocol id
    /// @param _transmitter address of transmitter to remove
    function removeTransmitter(
        bytes32 _protocolId,
        address _transmitter
    ) external onlyRole(STAKING_CONTRACTS) {
        if (allowedProtocolInfo[_protocolId].transmitters.remove(_transmitter)) {
            removeWatcher(_transmitter);
            address[] memory toRemove = new address[](1);
            toRemove[0] = _transmitter;
            uint i;
            for (; i < allowedProtocolInfo[_protocolId].chainIds.length; ) {
                proposeHelper.proposeRemoveTransmitters(
                    _protocolId,
                    allowedProtocolInfo[_protocolId].chainIds[i],
                    toRemove
                );
                unchecked {
                    ++i;
                }
            }
            emit RemoveTransmitter(_protocolId, _transmitter);
        }
    }

    /// @notice Setting of target rate
    /// @param _protocolId protocol id
    /// @param _rate target rate with 10000 decimals
    function setConsensusTargetRate(
        bytes32 _protocolId,
        uint256 _rate
    ) external onlyRole(STAKING_CONTRACTS) {
        allowedProtocolInfo[_protocolId].consensusTargetRate = _rate;
        uint _n = allowedProtocolInfo[_protocolId].chainIds.length;
        for (uint i; i < _n; ) {
            proposeHelper.proposeSetConsensusTargetRate(
                _protocolId,
                allowedProtocolInfo[_protocolId].chainIds[i],
                _rate
            );
            unchecked {
                ++i;
            }
        }
        emit SetConsensusTargetRate(_protocolId, _rate);
    }

    /*** GETERS ***/

    /// @notice getter of operation data
    /// @param opHash operation hash id
    /// @return Operation Data struct
    function getOpData(uint256 opHash) public view returns (OperationLib.OperationData memory) {
        return operations[opHash].operationData;
    }

    /// @notice getter of operation proofs
    /// @param opHash operation hash id
    /// @return current array of transmitter's signatures
    function getProofInfo(uint256 opHash) public view returns (ProofInfo memory) {
        return operations[opHash].proofInfo;
    }

    /*** LOGIC FUNCTIONS ***/
    /// @notice Get array of opHashes, check it was approved and returns array of result
    /// @param opHashArray array of operation hashes
    /// @return resultArray array of bool values indicates that operation was approved or not
    function checkOperationsApproveStatus(
        uint256[] calldata opHashArray
    ) external view returns (bool[] memory resultArray) {
        resultArray = new bool[](opHashArray.length);
        for (uint i; i < opHashArray.length; ) {
            resultArray[i] = operations[opHashArray[i]].proofInfo.isApproved;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Get array of opHashes, check it was executed and returns array of result
    /// @param opHashArray array of operation hashes
    /// @return resultArray array of bool values indicates that operation was executed or not
    function checkOperationsExecuteStatus(
        uint256[] calldata opHashArray
    ) external view returns (bool[] memory resultArray) {
        resultArray = new bool[](opHashArray.length);
        for (uint i; i < opHashArray.length; ) {
            resultArray[i] = operations[opHashArray[i]].proofInfo.isExecuted;
            unchecked {
                ++i;
            }
        }
    }

    /// @notice recover and check transmitter's signature
    /// @param transmitter transmitter's address
    /// @param opHash hash of signer data
    /// @param sig transmitter's signature
    function checkOperationSignature(
        address transmitter,
        bytes32 opHash,
        OperationLib.Signature memory sig
    ) internal pure returns (bool) {
        if (transmitter == ecrecover(opHash, sig.v, sig.r, sig.s)) return true;
        else return false;
    }

    /// @notice proposing an operation/approve an operation/give an operation of status approved
    /// @dev 0xe1b3d28a
    /// @param opData operation data
    /// @param sig transmitter's signature
    function proposeOperation(
        OperationLib.OperationData calldata opData,
        OperationLib.Signature calldata sig
    )
        external
        onlyAllowedProtocol(opData.protocolId, opData.destChainId, opData.protocolAddr)
        onlyAllowedTransmitter(opData.protocolId)
    {
        if (opData.protocolAddr.length > OperationLib.ADDRESS_MAX_LEN) {
            revert MasterSmartContract__AddrTooBig(opData.protocolId);
        }
        // if (opData.functionSelector.length > OperationLib.SELECTOR_MAX_LEN) {
        //     revert MasterSmartContract__SelectorTooBig(opData.protocolId);
        // }
        if (opData.params.length > OperationLib.PARAMS_MAX_LEN) {
            revert MasterSmartContract__ParamsTooBig(opData.protocolId);
        }
        if (proposeHelper.govContractAddresses(opData.destChainId).length == 0) {
            revert MasterSmartContract__InvalidChainId(opData.destChainId);
        }
        bytes32 protocolId = protocolAddressToProtocolId[opData.destChainId][opData.protocolAddr];
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                opData.protocolId,
                opData.meta,
                opData.srcChainId,
                opData.srcBlockNumber,
                opData.srcOpTxId,
                opData.nonce,
                opData.destChainId,
                opData.protocolAddr,
                opData.functionSelector,
                opData.params,
                opData.reserved
            )
        );
        bytes32 opHashBytes = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );
        uint256 opHash = uint256(opHashBytes);
        address msgSender = _msgSender();
        if (!checkOperationSignature(msgSender, opHashBytes, sig))
            revert MasterSmartContract__SignatureCheckFailed(opHash, msgSender);

        // place bet for operation proof
        betManager.placeBet(protocolId, _msgSender(), BetManager.BetType.Msg, opHash);

        // cache in memory for optimization
        Operation memory operation = operations[opHash];

        bool alreadyApproved = false;

        uint currentRound = stakingManager.round();

        if (operation.operationData.protocolAddr.length == 0) {
            address[] memory transmitters = new address[](1);
            address[] memory watchers = new address[](0);
            OperationLib.Signature[] memory sigs = new OperationLib.Signature[](1);
            transmitters[0] = _msgSender();
            sigs[0] = sig;
            operations[opHash] = Operation(
                ProofInfo(false, false, 1, 0, currentRound, 0, transmitters, watchers, sigs),
                opData
            );

            emit NewOperation(protocolId, opHash, opData.meta, msgSender);
        } else {
            // we are waiting for collecting more than neccessary sigs. it's more secure and stable
            if (operation.proofInfo.isApproved) {
                alreadyApproved = true;
                if (block.number > operation.proofInfo.approveBlockNumber + 1) {
                    revert MasterSmartContract__OperationIsAlreadyApproved(opHash);
                }
            }
            uint _n = operation.proofInfo.proofedTransmitters.length;
            uint i;
            for (; i < _n; ) {
                address proofedTransmitter = operation.proofInfo.proofedTransmitters[i];
                if (proofedTransmitter == msgSender) {
                    revert MasterSmartContract__TransmitterIsAlreadyApproved(msgSender, opHash);
                }
                unchecked {
                    ++i;
                }
            }
            // if new round was detected and operation still not approved,
            // we need to remove proofs and refund bets for removed transmitters
            if (!operation.proofInfo.isApproved && operation.proofInfo.round != currentRound) {
                address[] memory newTransmitters = new address[](_n + 1);
                OperationLib.Signature[] memory newSigs = new OperationLib.Signature[](_n + 1);
                uint k;
                delete i;
                for (; i < _n; ) {
                    address proofedTransmitter = operation.proofInfo.proofedTransmitters[i];
                    if (isAllowedTransmitter(protocolId, proofedTransmitter)) {
                        newTransmitters[k] = proofedTransmitter;
                        newSigs[k] = operation.proofInfo.transmitterSigs[i];
                        unchecked {
                            ++k;
                        }
                    } else {
                        betManager.refundBet(protocolId, opHash, proofedTransmitter);
                    }
                    unchecked {
                        ++i;
                    }
                }

                newTransmitters[k] = msgSender;
                newSigs[k] = sig;
                unchecked {
                    ++k;
                }

                assembly {
                    mstore(newTransmitters, k)
                    mstore(newSigs, k)
                }

                operations[opHash].proofInfo.proofedTransmitters = newTransmitters;
                operations[opHash].proofInfo.transmitterSigs = newSigs;
                operations[opHash].proofInfo.proofsCount = uint32(newTransmitters.length);

                operations[opHash].proofInfo.round = currentRound;
            } else {
                operations[opHash].proofInfo.proofedTransmitters.push(msgSender);
                operations[opHash].proofInfo.transmitterSigs.push(sig);
                unchecked {
                    ++operations[opHash].proofInfo.proofsCount;
                }
            }

            emit NewProof(protocolId, opHash, msgSender);
        }

        if (!alreadyApproved) {
            // check
            uint256 consensusRate = (operations[opHash].proofInfo.proofsCount * rateDecimals) /
                allowedProtocolInfo[protocolId].transmitters.length();
            if (consensusRate >= allowedProtocolInfo[protocolId].consensusTargetRate) {
                operations[opHash].proofInfo.isApproved = true;
                operations[opHash].proofInfo.approveBlockNumber = block.number;
                emit ProposalApproved(protocolId, opHash);
            }
        }
    }

    /// @notice approve operation was executed
    /// @param opHash 1
    function approveOperationExecuting(uint256 opHash) external onlyAllowedWatcher {
        // cache in memory for optimization
        Operation memory operation = operations[opHash];

        if (operation.operationData.protocolId == 0) {
            revert MasterSmartContract__OperationDoesNotExist(opHash);
        }
        if (!operation.proofInfo.isApproved) {
            revert MasterSmartContract__OpIsNotApproved(opHash);
        }
        if (operation.proofInfo.isExecuted) {
            return;
            //revert MasterSmartContract__OpExecutionAlreadyApproved(opHash);
        }
        uint _n = operation.proofInfo.proofedWatchers.length;
        for (uint i; i < _n; ) {
            if (operation.proofInfo.proofedWatchers[i] == _msgSender()) {
                revert MasterSmartContract__WatcherIsAlreadyApproved(_msgSender(), opHash);
            }
            unchecked {
                ++i;
            }
        }
        operations[opHash].proofInfo.proofedWatchers.push(_msgSender());
        ++operations[opHash].proofInfo.watchersProofCount;

        uint256 consensusRate = (operations[opHash].proofInfo.watchersProofCount * rateDecimals) /
            numberOfAllowedWatchers;

        if (consensusRate >= watchersConsensusTargetRate) {
            bytes32 protocolId = operation.operationData.protocolId;
            operations[opHash].proofInfo.isExecuted = true;
            if (PhotonOperationMetaLib.isInOrder(operation.operationData.meta)) {
                lastExecutedOpNonceInOrder[protocolId][
                    operation.operationData.srcChainId
                ] = operation.operationData.nonce;
            }
            // release transmitters bets
            betManager.releaseBetsAndReward(
                protocolId,
                operations[opHash].proofInfo.proofedTransmitters,
                opHash
            );
            emit ProposalExecuted(protocolId, opHash);
        }
    }

    function isAllowedTransmitter(
        bytes32 _protocolId,
        address _transmitter
    ) public view returns (bool) {
        return allowedProtocolInfo[_protocolId].transmitters.contains(_transmitter);
    }

    function isPaused(bytes32 protocolId) external view returns (bool) {
        return allowedProtocolInfo[protocolId].isPaused;
    }

    function isInitGlobal(bytes32 protocolId) external view returns (bool) {
        return allowedProtocolInfo[protocolId].isInit;
    }

    function numberOfAllowedTransmitters(bytes32 protocolId) external view returns (uint) {
        return allowedProtocolInfo[protocolId].transmitters.length();
    }

    function isInited(bytes32 protocolId, uint chainId) public view returns (bool) {
        return
            allowedProtocolInfo[protocolId].initOnChainInfo[chainId].stage ==
            InitOnChainStages.Inited;
    }

    /// @notice get transmitters array allowed on specified protocol
    /// @param protocolId protocol id
    function getTransmitters(bytes32 protocolId) external view returns (address[] memory) {
        if (!allowedProtocolInfo[protocolId].isInit)
            revert MasterSmartContract__ProtocolIsNotInited(protocolId);
        return allowedProtocolInfo[protocolId].transmitters.values();
    }

    /// @notice get protocol info
    /// @param protocolId protocol id
    /// @return isInit is protocol inited
    /// @return isPaused is protocol paused
    /// @return consensusTargetRate consensus target rate
    /// @return chainIds array of chain ids where protocol is allowed
    /// @return transmitters array of allowed transmitters
    function getProtocolInfo(
        bytes32 protocolId
    ) public view returns (bool, bool, uint256, uint256[] memory, address[] memory) {
        return (
            allowedProtocolInfo[protocolId].isInit,
            allowedProtocolInfo[protocolId].isPaused,
            allowedProtocolInfo[protocolId].consensusTargetRate,
            allowedProtocolInfo[protocolId].chainIds,
            allowedProtocolInfo[protocolId].transmitters.values()
        );
    }

    function getProtocolInitOnChainInfo(bytes32 _protocolId, uint256 _chainId) public view returns (InitOnChainInfo memory) {
        return allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId];
    }

    // function debugSetProtocolNotInitedOnChain(bytes32 _protocolId, uint256 _chainId) external {
    //     allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage = InitOnChainStages.NotInited;
    // }

    function debug_UnstuckInitOnChain(bytes32 _protocolId, uint256 _chainId) external onlyRole(ADMIN) {
        if (allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage == InitOnChainStages.OnInition) {
            allowedProtocolInfo[_protocolId].initOnChainInfo[_chainId].stage = InitOnChainStages.NotInited;
        }
    }
}
