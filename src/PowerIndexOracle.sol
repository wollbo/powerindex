// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract PowerIndexOracle {
    // indexId => areaId => dateNum => commitment
    mapping(bytes32 => mapping(bytes32 => mapping(uint32 => Commitment))) public commitments;

    struct Commitment {
        int256 value;        // scaled fixed-point value
        bytes32 dataHash;    // hash of canonical preimage / evidence pointer
        address reporter;    // who reported
        uint64 reportedAt;   // timestamp
    }

    event DailyIndexCommitted(
        bytes32 indexed indexId,
        bytes32 indexed areaId,
        uint32 indexed dateNum,
        int256 value,
        bytes32 dataHash,
        address reporter,
        uint64 reportedAt
    );

    error AlreadyCommitted();
    error InvalidDate();

    function commitDailyIndex(
        bytes32 indexId,
        bytes32 areaId,
        uint32 dateNum,   // YYYYMMDD
        int256 value,
        bytes32 dataHash
    ) external {
        // Minimal date sanity: YYYYMMDD must be plausible
        // (keeps obvious garbage out; can tighten later)
        if (dateNum < 19000101 || dateNum > 30000101) revert InvalidDate();

        Commitment storage c = commitments[indexId][areaId][dateNum];
        if (c.reportedAt != 0) revert AlreadyCommitted();

        uint64 ts = uint64(block.timestamp);
        commitments[indexId][areaId][dateNum] = Commitment({
            value: value,
            dataHash: dataHash,
            reporter: msg.sender,
            reportedAt: ts
        });

        emit DailyIndexCommitted(indexId, areaId, dateNum, value, dataHash, msg.sender, ts);
    }

    function getCommitment(bytes32 indexId, bytes32 areaId, uint32 dateNum)
        external
        view
        returns (Commitment memory)
    {
        return commitments[indexId][areaId][dateNum];
    }
}
