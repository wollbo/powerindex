// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IReceiver } from "../interfaces/IReceiver.sol";

contract LocalCREForwarder {
    address public owner;
    mapping(address => bool) public isAllowedSender;

    error NotOwner();
    error SenderNotAllowed();

    constructor() {
        owner = msg.sender;
    }

    function setAllowedSender(address sender, bool allowed) external {
        if (msg.sender != owner) revert NotOwner();
        isAllowedSender[sender] = allowed;
    }

    function forward(address consumer, bytes calldata metadata, bytes calldata report) external {
        if (!isAllowedSender[msg.sender]) revert SenderNotAllowed();
        IReceiver(consumer).onReport(metadata, report);
    }
}
