// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IIndexConsumer {
    function commitments(bytes32 indexId, bytes32 areaId, uint32 yyyymmdd)
        external
        view
        returns (bytes32 datasetHash, int256 value1e6, address reporter, uint64 reportedAt);
}
