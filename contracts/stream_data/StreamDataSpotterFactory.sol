// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./StreamDataSpotter.sol";
import "../staking/ExternalDeveloperHub.sol";
import "../staking/BetManager.sol";
import "./MasterStreamDataSpotter.sol";
import "../MasterSmartContract.sol";

contract StreamDataSpotterFactory is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    OwnableUpgradeable
{

    error StreamDataSpotterFactory__SpotterDoesNotExist(bytes32, bytes32);
    error StreamDataSpotterFactory__SpotterAlreadyExist(bytes32, bytes32);
    error StreamDataSpotterFactory__LengthMismatch(uint256, uint256);
    error StreamDataSpotterFactory__SpotterDisabledSettingAllowedKeys(bytes32, bytes32);
    error StreamDataSpotterFactory__CallerIsNotSpotter();
    error StreamDataSpotterFactory__CallerIsNotAllowedTransmitter();
    error StreamDataSpotterFactory__CallerIsNotAllowedProtocolOwner();
    error StreamDataSpotterFactory__CallerIsNotAllowedFinalizer();
    error StreamDataSpotterFactory__InvalidConsensusRate();
    error StreamDataSpotterFactory__FinalizerZeroAddress();
    error StreamDataSpotterFactory__FinalizerAlreadyExist();
    error StreamDataSpotterFactory__FinalizerDoesNotExist();

    event NewStreamDataSpotter(
        bytes32 indexed protocolId,
        bytes32 indexed sourceId,
        address spotter,
        address processingLib,
        uint256 consensusRate,
        uint256 minFinalizationInterval,
        bytes32[] allowedKeys,
        bool onlyAllowedKeys
    );
    event SetSpotterConsensusRate(bytes32 indexed protocolId, bytes32 indexed sourceId, uint256 newConsensusRate);
    event SetMinFinalizationInterval(
        bytes32 indexed protocolId,
        bytes32 indexed sourceId,
        uint256 newMinFinalizationInterval
    );
    event SetAllowedKeys(bytes32 indexed protocolId, bytes32 indexed sourceId, bytes32[] allowedKeys);

    bytes32 public constant ADMIN = keccak256("ADMIN");
    bytes32 public constant ROUND_MANAGER = keccak256("ROUND_MANAGER");

    struct PendedConsensusRate {
        bytes32 protocolId;
        bytes32 sourceId;
        uint256 newConsensusRate;
    }
    struct PendedMinFinalizationInterval {
        bytes32 protocolId;
        bytes32 sourceId;
        uint256 newMinFinalizationInterval;
    }

    PendedConsensusRate[] public pendedConsensusRate;
    PendedMinFinalizationInterval[] public pendedMinFinalizationInterval;

    /// @notice public map of deployed spotters, protocolId => sourceId => spotter
    mapping(bytes32 => mapping(bytes32 => StreamDataSpotter)) internal spottersMap;
    /// @notice mapping of allowed finalizers for a given protocol
    /// Finalizers are addresses that are allowed to finalize StreamDataSpotters for a given protocol
    mapping(bytes32 protocolId => mapping(address finalizer => bool isAllowed)) public allowedFinalizers;


    mapping(address => bool) public isSpotter;

    StreamDataSpotter[] public allSpotters;
    ExternalDeveloperHub public externalDeveloperHub;
    MasterSmartContract public masterSmartContract;
    MasterStreamDataSpotter public masterStreamDataSpotter;
    BetManager public betManager;

    function __chainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    /// @notice Initializer
    /// @param initAddr 0: admin, 1: externalDeveloperHub, 2: MasterSmartContract, 3: BetManager, 4: RoundManager
    function initialize(address[5] calldata initAddr) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();

        _setRoleAdmin(ADMIN, ADMIN);
        _grantRole(ADMIN, initAddr[0]);
        externalDeveloperHub = ExternalDeveloperHub(initAddr[1]);
        masterSmartContract = MasterSmartContract(initAddr[2]);
        betManager = BetManager(initAddr[3]);
        _grantRole(ROUND_MANAGER, initAddr[4]);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN) {}

    function _onlyProtocolOwner(bytes32 protocolId) internal view {
        if (_msgSender() != externalDeveloperHub.getProtocolOwner(protocolId)) {
            revert StreamDataSpotterFactory__CallerIsNotAllowedProtocolOwner();
        }
    }

    modifier onlyProtocolOwner(bytes32 protocolId) {
        _onlyProtocolOwner(protocolId);
        _;
    }

    function _onlySpotter() internal view {
        if (!isSpotter[_msgSender()]) {
            revert StreamDataSpotterFactory__CallerIsNotSpotter();
        }
    }

    modifier onlySpotter() {
        _onlySpotter();
        _;
    }

    /*
     * Admin functions
     */

    /// @notice sets masterStreamDataSpotter contract address
    /// @param newMasterStreamDataSpotter MasterStreamDataSpotter contract address
    function setMasterStreamDataSpotter(
        address newMasterStreamDataSpotter
    ) external onlyRole(ADMIN) {
        masterStreamDataSpotter = MasterStreamDataSpotter(newMasterStreamDataSpotter);
    }

    /// @notice calls betManager to place bet for Transmitter, caller must be StreamDataSpotter
    /// @param protocolId - protocol id
    /// @param transmitter - transmitter address
    /// @param betType - bet type
    /// @param opHash - operation hash
    function placeBet(
        bytes32 protocolId,
        address transmitter,
        BetManager.BetType betType,
        uint256 opHash
    ) external onlySpotter {
        betManager.placeBet(protocolId, transmitter, betType, opHash);
    }

    /// @notice calls betManager to release bets and reward agents, caller must be StreamDataSpotter
    /// @param protocolId - protocol id
    /// @param agentTransmitterBets - array of transmitters
    /// @param opHash - operation hash
    function releaseBetsAndReward(
        bytes32 protocolId,
        address[] memory agentTransmitterBets,
        uint256 opHash
    ) external onlySpotter {
        betManager.releaseBetsAndReward(protocolId, agentTransmitterBets, opHash);
    }

    /*
     * Executor functions
     */

    /// @notice Executor function that attempts to trigger update for a given dataKey asset
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKey data key
    function finalizeData(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32 dataKey
    ) external {
        if (!allowedFinalizers[protocolId][_msgSender()]) {
            revert StreamDataSpotterFactory__CallerIsNotAllowedFinalizer();
        }

        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];
        spotter.finalizeData(dataKey);
    }

    /// @notice Executor function that attempts to trigger update for a given dataKey asset
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKey data key
    function finalizeDataBatch(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32[] calldata dataKey
    ) external {
        if (!allowedFinalizers[protocolId][_msgSender()]) {
            revert StreamDataSpotterFactory__CallerIsNotAllowedFinalizer();
        }

        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];

        for (uint i = 0; i < dataKey.length; i++) {
            spotter.finalizeData(dataKey[i]);
        }
    }

    /*
     * Transmitter functions
     */

    /// @notice Transmitter function that allows to propose multiple assets in
    /// a single transaction for a given sourceId.
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKeys array of dataKeys to propose data for
    /// @param values array of values to propose, related to dataKeys
    function proposeMultipleData(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32[] calldata dataKeys,
        bytes[] calldata values
    ) external {
        // Check if caller is allowed transmitter
        if (!masterSmartContract.isAllowedTransmitter(protocolId, _msgSender())) {
            revert StreamDataSpotterFactory__CallerIsNotAllowedTransmitter();
        }

        // Validate dataKey and value are the same length
        if (dataKeys.length != values.length) {
            revert StreamDataSpotterFactory__LengthMismatch(dataKeys.length, values.length);
        }

        // Propose with data provided
        for (uint256 i; i < dataKeys.length;) {

            StreamDataSpotter spotter = spottersMap[protocolId][sourceId];

            // Confirm that spotter exists
            if (address(spotter) == address(0)) {
                revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
            }

            spotter.proposeData(_msgSender(), dataKeys[i], values[i]);

            unchecked {
                ++i;
            }
        }

    }

    /// @notice Transmitter function that allows to propose data for a given dataKey asset
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param dataKey data key
    /// @param value data value
    function proposeData(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32 dataKey,
        bytes calldata value
    ) external {
        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];
        if (address(spotter) == address(0)) {
            revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
        }

        if (!masterSmartContract.isAllowedTransmitter(protocolId, _msgSender())) {
            revert StreamDataSpotterFactory__CallerIsNotAllowedTransmitter();
        }

        spotter.proposeData(_msgSender(), dataKey, value);
    }

    /*
     * ExternalDeveloper functions
     */

    /// @notice function that adds allowed data finalizer for a given protocol
    /// @param protocolId protocol id
    /// @param finalizer address of the finalizer
    function addFinalizer(bytes32 protocolId, address finalizer) external onlyProtocolOwner(protocolId) {
        if (finalizer == address(0)) {
            revert StreamDataSpotterFactory__FinalizerZeroAddress();
        }
        if (allowedFinalizers[protocolId][finalizer]) {
            revert StreamDataSpotterFactory__FinalizerAlreadyExist();
        }
        allowedFinalizers[protocolId][finalizer] = true;
    }

    /// @notice function that removes data finalizer from protocol
    /// @param protocolId protocol id
    /// @param finalizer address of the finalizer
    function removeFinalizer(bytes32 protocolId, address finalizer) external onlyProtocolOwner(protocolId) {
        if (!allowedFinalizers[protocolId][finalizer]) {
            revert StreamDataSpotterFactory__FinalizerDoesNotExist();
        }
        allowedFinalizers[protocolId][finalizer] = false;
    }

    /// @notice Deploy spotter contract for the new sourceID
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param processingLib address of deployed processing lib contract to be used for that spotter
    /// @param consensusRate consensus rate of agents necessary for update to happend
    /// @param allowedKeys array of allowed data keys, only existing datakeys can be used to vote the data for
    /// @param onlyAllowedKeys if false, any key can be used as data key in DataSpotter 
    function deployNewStreamDataSpotter(
        bytes32 protocolId,
        bytes32 sourceId,
        address processingLib,
        uint256 consensusRate,
        uint256 minFinalizationInterval,
        bytes32[] calldata allowedKeys,
        bool onlyAllowedKeys
    ) public onlyProtocolOwner(protocolId) returns (address) {
        // if (address(spottersMap[protocolId][sourceId]) != address(0)) {
        //     revert StreamDataSpotterFactory__SpotterAlreadyExist(protocolId, sourceId);
        // }

        StreamDataSpotter newSource = new StreamDataSpotter(
            protocolId,
            sourceId,
            processingLib,
            address(masterSmartContract),
            consensusRate,
            minFinalizationInterval,
            onlyAllowedKeys
        );
        spottersMap[protocolId][sourceId] = newSource;
        isSpotter[address(newSource)] = true;
        allSpotters.push(newSource);

        if (onlyAllowedKeys) {
            masterStreamDataSpotter.setAllowedKeys(protocolId, sourceId, allowedKeys);
        }

        emit NewStreamDataSpotter(protocolId, sourceId, address(newSource), processingLib, consensusRate, minFinalizationInterval, allowedKeys, onlyAllowedKeys);
        return address(newSource);
    }

    /// @notice changes consensus rate for a spotter
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param newConsensusRate new consensus rate
    function setSpotterConsensusRate(
        bytes32 protocolId,
        bytes32 sourceId,
        uint256 newConsensusRate
    ) external onlyProtocolOwner(protocolId) {
        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];
        if (address(spotter) == address(0)) {
            revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
        }

        if (newConsensusRate <= 5000 || newConsensusRate > 10000) {
            revert StreamDataSpotterFactory__InvalidConsensusRate();
        }

        bool pended = false;
        for (uint i; i < pendedConsensusRate.length; ) {
            if (
                pendedConsensusRate[i].protocolId == protocolId &&
                pendedConsensusRate[i].sourceId == sourceId
            ) {
                pendedConsensusRate[i].newConsensusRate = newConsensusRate;
                pended = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (!pended) {
            pendedConsensusRate.push(PendedConsensusRate(protocolId, sourceId, newConsensusRate));
        }
    }

    /// @notice changes minimum finalization interval for a spotter
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param newMinFinalizationInterval new minimum finalization interval
    function setMinFinalizationInterval(
        bytes32 protocolId,
        bytes32 sourceId,
        uint256 newMinFinalizationInterval
    ) external onlyProtocolOwner(protocolId) {
        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];
        if (address(spotter) == address(0)) {
            revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
        }
        bool pended = false;
        for (uint i; i < pendedMinFinalizationInterval.length; ) {
            if (
                pendedMinFinalizationInterval[i].protocolId == protocolId &&
                pendedMinFinalizationInterval[i].sourceId == sourceId
            ) {
                pendedMinFinalizationInterval[i]
                    .newMinFinalizationInterval = newMinFinalizationInterval;
                pended = true;
                break;
            }
            unchecked {
                ++i;
            }
        }
        if (!pended) {
            pendedMinFinalizationInterval.push(
                PendedMinFinalizationInterval(protocolId, sourceId, newMinFinalizationInterval)
            );
        }
    }

    /// @notice set allowed keys for deployed spotter
    /// @param protocolId protocol id
    /// @param sourceId source id
    /// @param allowedKeys array of new allowed datakeys
    function setAllowedKeys(
        bytes32 protocolId,
        bytes32 sourceId,
        bytes32[] calldata allowedKeys
    ) external onlyProtocolOwner(protocolId) {
        StreamDataSpotter spotter = StreamDataSpotter(getSpotter(protocolId, sourceId));
        if (address(spotter) == address(0)) {
            revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
        }

        if (!spotter.onlyAllowedKeys()) {
            revert StreamDataSpotterFactory__SpotterDisabledSettingAllowedKeys(protocolId, sourceId);
        }

        masterStreamDataSpotter.setAllowedKeys(protocolId, sourceId, allowedKeys);
        emit SetAllowedKeys(protocolId, sourceId, allowedKeys);
    }

    /*
     * Unprivileged functions
     */

    function allSpottersLength() external view returns (uint256) {
        return allSpotters.length;
    }

    /// @notice get spotter contract address for source id
    /// @param protocolId protocol id
    /// @param sourceId source id
    function getSpotter(bytes32 protocolId, bytes32 sourceId) public view returns (address) {
        return address(spottersMap[protocolId][sourceId]);
    }

    function getConsensusRate(
        bytes32 protocolId,
        bytes32 sourceId
    ) external view returns (uint256) {
        StreamDataSpotter spotter = spottersMap[protocolId][sourceId];
        if (address(spotter) == address(0)) {
            revert StreamDataSpotterFactory__SpotterDoesNotExist(protocolId, sourceId);
        }
        return spotter.consensusRate();
    }

    function turnRound() external onlyRole(ROUND_MANAGER) {
        uint i;
        for (; i < pendedConsensusRate.length; ) {
            StreamDataSpotter spotter = spottersMap[pendedConsensusRate[i].protocolId][
                pendedConsensusRate[i].sourceId
            ];
            spotter.setConsensusRate(pendedConsensusRate[i].newConsensusRate);
            emit SetSpotterConsensusRate(
                pendedConsensusRate[i].protocolId,
                pendedConsensusRate[i].sourceId,
                pendedConsensusRate[i].newConsensusRate
            );
            unchecked {
                ++i;
            }
        }
        delete pendedConsensusRate;
        delete i;
        for (; i < pendedMinFinalizationInterval.length; ) {
            StreamDataSpotter spotter = spottersMap[pendedMinFinalizationInterval[i].protocolId][
                pendedMinFinalizationInterval[i].sourceId
            ];
            spotter.setMinFinalizationInterval(
                pendedMinFinalizationInterval[i].newMinFinalizationInterval
            );
            emit SetMinFinalizationInterval(
                pendedMinFinalizationInterval[i].protocolId,
                pendedMinFinalizationInterval[i].sourceId,
                pendedMinFinalizationInterval[i].newMinFinalizationInterval
            );
            unchecked {
                ++i;
            }
        }
        delete pendedMinFinalizationInterval;
    }
}
