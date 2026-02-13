// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { DailyIndexConsumer } from "src/DailyIndexConsumer.sol";
import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";

contract ForwarderGatingTest is Test {
    LocalCREForwarder forwarder;
    DailyIndexConsumer consumer;

    address CRE_SENDER = address(0xBEEF);
    address ATTACKER   = address(0xCAFE);

    bytes32 constant INDEX_ID = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1"));
    bytes32 constant AREA_ID  = keccak256(bytes("NO1"));
    uint32  constant DATE_NUM = 20260128;
    int256  constant VALUE_1E6 = int256(42_420_000);

    function setUp() public {
        forwarder = new LocalCREForwarder();
        consumer = new DailyIndexConsumer(address(forwarder));

        // allow the “CRE sender”
        forwarder.setAllowedSender(CRE_SENDER, true);
    }

    function _report() internal pure returns (bytes memory) {
        // Use whatever you now call it: datasetHash / dataHash
        bytes32 datasetHash = keccak256(abi.encodePacked("demo"));
        return abi.encode(INDEX_ID, DATE_NUM, AREA_ID, VALUE_1E6, datasetHash);
    }

    function testConsumerRejectsDirectCall() public {
        vm.expectRevert(DailyIndexConsumer.OnlyForwarder.selector);
        consumer.onReport(hex"", _report());
    }

    function testForwarderRejectsUnauthorizedSender() public {
        vm.prank(ATTACKER);
        vm.expectRevert(LocalCREForwarder.SenderNotAllowed.selector);
        forwarder.forward(address(consumer), hex"", _report());
    }

    function testHappyPathAllowedSenderForwards() public {
        // consumer records tx.origin, so set both msg.sender and tx.origin
        vm.prank(CRE_SENDER, CRE_SENDER);
        forwarder.forward(address(consumer), hex"", _report());

        (bytes32 datasetHash, int256 value1e6, address reporter, uint64 reportedAt) =
            consumer.commitments(INDEX_ID, AREA_ID, DATE_NUM);

        assertEq(value1e6, VALUE_1E6);
        assertTrue(datasetHash != bytes32(0));
        assertEq(reporter, CRE_SENDER);
        assertGt(reportedAt, 0);
    }

    function testDuplicateStillReverts() public {
        vm.prank(CRE_SENDER, CRE_SENDER);
        forwarder.forward(address(consumer), hex"", _report());

        vm.prank(CRE_SENDER, CRE_SENDER);
        vm.expectRevert(DailyIndexConsumer.AlreadyCommitted.selector);
        forwarder.forward(address(consumer), hex"", _report());
    }
}
