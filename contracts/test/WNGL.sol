// SPDX-License-Identifier: BSL 1.1
pragma solidity ^0.8.19;

import "./EntangleToken.sol";

contract WNGL is EntangleToken {
    constructor() EntangleToken() {}

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 _amount) public {
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(_amount);
    }
}