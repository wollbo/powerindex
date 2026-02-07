// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DailyIndexConsumer.sol";

contract DailyIndexConsumerTest is Test {
    DailyIndexConsumer consumer;

    bytes32 constant INDEX_ID = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1"));
    bytes32 constant AREA_ID  = keccak256(bytes("NO1"));
    uint32 constant DATE_NUM  = 20260125;
    uint256 constant VALUE_1E6 = 42_420_000;

    function setUp() public {
        consumer = new DailyIndexConsumer();
    }

    function _dataHash() internal pure returns (bytes32) {
        // Keep this canonical string in sync with workflow logs
        return keccak256(abi.encodePacked("NORDPOOL_DAYAHEAD_AVG_V1|NO1|20260125|EUR|42420000"));
    }

    function _report() internal pure returns (bytes memory) {
        return abi.encode(INDEX_ID, DATE_NUM, AREA_ID, VALUE_1E6, _dataHash());
    }

    function testOnReportStoresCommitment() public {
        // Act
        consumer.onReport(hex"", _report());

        // Assert storage (public mapping getter)
        (bytes32 dataHash, uint256 value1e6, address reporter, uint64 reportedAt) =
            consumer.commitments(INDEX_ID, AREA_ID, DATE_NUM);

        assertEq(dataHash, _dataHash());
        assertEq(value1e6, VALUE_1E6);
        assertEq(reporter, address(this));
        assertGt(reportedAt, 0);
    }

    function testOnReportEmitsEvent() public {
        bytes32 dh = _dataHash();

        vm.expectEmit(true, true, true, true);
        emit DailyIndexConsumer.DailyIndexCommitted(
            INDEX_ID,
            AREA_ID,
            DATE_NUM,
            VALUE_1E6,
            dh,
            address(this),
            uint64(block.timestamp) // note: this is checked loosely by expectEmit? see below
        );

        // The reportedAt timestamp inside the event is set during execution,
        // so to avoid brittle exact matching, we can just not compare it strictly:
        // Alternative approach below.

        consumer.onReport(hex"", _report());
    }

    function testOnReportEmitsEventRobust() public {
        // Robust event assertion: record logs and decode the event.
        vm.recordLogs();
        consumer.onReport(hex"", _report());
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find the first log from this contract with our event signature
        bytes32 sig = keccak256("DailyIndexCommitted(bytes32,bytes32,uint32,uint256,bytes32,address,uint64)");

        bool found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter != address(consumer)) continue;
            if (entries[i].topics.length == 0) continue;
            if (entries[i].topics[0] != sig) continue;

            // topics[1]=indexId, topics[2]=areaId, topics[3]=yyyymmdd
            assertEq(entries[i].topics[1], INDEX_ID);
            assertEq(entries[i].topics[2], AREA_ID);
            assertEq(entries[i].topics[3], bytes32(uint256(DATE_NUM)));

            // Decode data: (value1e6, dataHash, reporter, reportedAt) because indexed fields are in topics
            (uint256 value1e6, bytes32 dataHash, address reporter, uint64 reportedAt) =
                abi.decode(entries[i].data, (uint256, bytes32, address, uint64));

            assertEq(value1e6, VALUE_1E6);
            assertEq(dataHash, _dataHash());
            assertEq(reporter, address(this));
            assertGt(reportedAt, 0);

            found = true;
            break;
        }

        assertTrue(found, "DailyIndexCommitted event not found");
    }

    function testRevertOnDuplicate() public {
        consumer.onReport(hex"", _report());
        vm.expectRevert(DailyIndexConsumer.AlreadyCommitted.selector);
        consumer.onReport(hex"", _report());
    }
}
