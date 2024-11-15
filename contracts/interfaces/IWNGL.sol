//SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

interface IWNGL {
    function deposit() external payable;
    function withdraw(uint256) external;
}