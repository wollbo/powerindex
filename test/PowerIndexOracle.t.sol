// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import "../src/PowerIndexOracle.sol";

contract PowerIndexOracleTest is Test {
    PowerIndexOracle oracle;

    function setUp() public {
        oracle = new PowerIndexOracle();
    }

    function testCommitDailyIndex() public {
        bytes32 indexId = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1"));
        bytes32 areaId = keccak256(bytes("NO1"));
        uint32 dateNum = 20260125;
        int256 value = 4242; // 42.42 scaled by 100
        bytes32 dataHash = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1|NO1|20260125|EUR|4242"));

        oracle.commitDailyIndex(indexId, areaId, dateNum, value, dataHash);

        PowerIndexOracle.Commitment memory c = oracle.getCommitment(indexId, areaId, dateNum);
        assertEq(c.value, value);
        assertEq(c.dataHash, dataHash);
        assertEq(c.reporter, address(this));
        assertGt(c.reportedAt, 0);
    }

    function testRevertOnDuplicate() public {
        bytes32 indexId = keccak256(bytes("NORDPOOL_DAYAHEAD_AVG_V1"));
        bytes32 areaId = keccak256(bytes("NO1"));

        oracle.commitDailyIndex(indexId, areaId, 20260125, 4242, bytes32(0));
        vm.expectRevert(PowerIndexOracle.AlreadyCommitted.selector);
        oracle.commitDailyIndex(indexId, areaId, 20260125, 1111, bytes32(0));
    }
}
