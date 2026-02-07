// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DailyIndexConsumer.sol";

contract SendReportDemo is Script {
    function run() external {
        address consumerAddr = vm.envAddress("CONSUMER");
        DailyIndexConsumer consumer = DailyIndexConsumer(consumerAddr);

        // Inputs (with sensible defaults)
        string memory indexName = vm.envOr("INDEX_NAME", string("NORDPOOL_DAYAHEAD_AVG_V1"));
        string memory area = vm.envOr("AREA", string("NO1"));
        uint256 dateNumU = vm.envOr("DATE_NUM", uint256(20260125));

        uint256 value1e6 = vm.envOr("VALUE_1E6", uint256(42_420_000));

        bytes32 indexId = keccak256(bytes(indexName));
        bytes32 areaId  = keccak256(bytes(area));
        uint32 dateNum  = uint32(dateNumU);

        // Canonical preimage commits to the exact integer written on chain
        string memory preimage = string.concat(
            indexName, "|",
            area, "|",
            vm.toString(dateNumU), "|",
            "EUR", "|",
            vm.toString(value1e6)
        );

        bytes32 dataHash = keccak256(abi.encodePacked(preimage));

        bytes memory report = abi.encode(indexId, dateNum, areaId, value1e6, dataHash);

        vm.startBroadcast();
        consumer.onReport(hex"", report);
        vm.stopBroadcast();

        console2.log("Report sent to:", consumerAddr);
        console2.log("INDEX_NAME:", indexName);
        console2.log("AREA:", area);
        console2.log("DATE_NUM:", dateNumU);
        console2.log("VALUE_1E6:", value1e6);
        console2.log("preimage:", preimage);
        console2.logBytes32(dataHash);
    }
}
