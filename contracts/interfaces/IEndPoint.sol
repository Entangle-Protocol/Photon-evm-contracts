//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

interface IEndPoint {
    /// @notice protocol info struct
    struct AllowedProtocolInfo {
        bool isCreated;
        uint256 consensusTargetRate; // percentage of proofs div numberOfAllowedTransmitters which should be reached to approve operation. Scaled with 10000 decimals, e.g. 6000 is 60%
    }

    function numberOfAllowedTransmitters(bytes32 protocolId) external view returns (uint256);
    function allowedProtocolInfo(bytes32 protocolId) external view returns (bool isCreated, uint256 consensusTargetRate);
    function allowedTransmitters(bytes32 protocolId, address transmitter) external view returns (bool);

}
