// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IReceiver {
    function onReport(bytes calldata metadata, bytes calldata report) external;
}

contract DailyIndexConsumer is IReceiver {
    event DailyIndexCommitted(
        bytes32 indexed indexId,
        bytes32 indexed areaId,
        uint32 indexed yyyymmdd,
        uint256 value1e6,
        bytes32 dataHash,
        address reporter,
        uint64 reportedAt
    );

    struct Commitment {
        bytes32 dataHash;
        uint256 value1e6;
        address reporter;
        uint64 reportedAt;
    }

    // indexId => areaId => date => commitment
    mapping(bytes32 => mapping(bytes32 => mapping(uint32 => Commitment))) public commitments;

    error AlreadyCommitted();

    function onReport(bytes calldata /* metadata */, bytes calldata report) external override {
        (bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, uint256 value1e6, bytes32 dataHash) =
            abi.decode(report, (bytes32, uint32, bytes32, uint256, bytes32));

        Commitment storage c = commitments[indexId][areaId][yyyymmdd];
        if (c.reportedAt != 0) revert AlreadyCommitted();

        uint64 ts = uint64(block.timestamp);
        commitments[indexId][areaId][yyyymmdd] = Commitment({
            dataHash: dataHash,
            value1e6: value1e6,
            reporter: msg.sender,
            reportedAt: ts
        });

        emit DailyIndexCommitted(indexId, areaId, yyyymmdd, value1e6, dataHash, msg.sender, ts);
    }
}
