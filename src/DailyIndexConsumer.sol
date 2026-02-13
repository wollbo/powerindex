// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IReceiver } from "./interfaces/IReceiver.sol";

contract DailyIndexConsumer is IReceiver {
    event DailyIndexCommitted(
        bytes32 indexed indexId,
        bytes32 indexed areaId,
        uint32 indexed yyyymmdd,
        int256 value1e6,
        bytes32 datasetHash,
        address reporter,
        uint64 reportedAt
    );

    struct Commitment {
        bytes32 datasetHash;
        int256 value1e6;
        address reporter;
        uint64 reportedAt;
    }

    // indexId => areaId => date => commitment
    mapping(bytes32 => mapping(bytes32 => mapping(uint32 => Commitment))) public commitments;

    address public immutable forwarder;

    error AlreadyCommitted();
    error OnlyForwarder();

    constructor(address forwarder_) {
        forwarder = forwarder_;
    }

    function onReport(bytes calldata, bytes calldata report) external override {
        if (msg.sender != forwarder) revert OnlyForwarder();

        (bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, int256 value1e6, bytes32 datasetHash) =
            abi.decode(report, (bytes32, uint32, bytes32, int256, bytes32));

        Commitment storage c = commitments[indexId][areaId][yyyymmdd];
        if (c.reportedAt != 0) revert AlreadyCommitted();

        uint64 ts = uint64(block.timestamp);

        commitments[indexId][areaId][yyyymmdd] = Commitment({
            datasetHash: datasetHash,
            value1e6: value1e6,
            reporter: tx.origin, // optional: EOA initiator; or msg.sender
            reportedAt: ts
        });

        emit DailyIndexCommitted(indexId, areaId, yyyymmdd, value1e6, datasetHash, tx.origin, ts);
    }
}
