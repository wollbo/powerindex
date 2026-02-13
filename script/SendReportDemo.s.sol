// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";

contract SendReportDemo is Script {
    function run() external {
        address consumerAddr = vm.envAddress("CONSUMER");
        address forwarderAddr = vm.envAddress("FORWARDER");
        LocalCREForwarder forwarder = LocalCREForwarder(forwarderAddr);

        // Inputs
        string memory indexName = vm.envOr("INDEX_NAME", string("NORDPOOL_DAYAHEAD_AVG_V1"));
        string memory area = vm.envOr("AREA", string("NO1"));
        uint256 dateNumU = vm.envOr("DATE_NUM", uint256(20260125));

        // allow negatives in env by using string
        string memory valueStr = vm.envOr("VALUE_1E6_STR", string("42420000"));
        int256 value1e6 = vm.parseInt(valueStr);

        bytes32 indexId = keccak256(bytes(indexName));
        bytes32 areaId  = keccak256(bytes(area));
        uint32 dateNum  = uint32(dateNumU);

        // Demo datasetHash (for real, CRE will compute canonical bytes hash)
        bytes32 datasetHash = keccak256(abi.encodePacked("demo-dataset|", indexName, "|", area, "|", vm.toString(dateNumU), "|", valueStr));

        bytes memory report = abi.encode(indexId, dateNum, areaId, value1e6, datasetHash);

        vm.startBroadcast();
        forwarder.forward(consumerAddr, hex"", report);
        vm.stopBroadcast();

        console2.log("Report sent via forwarder:", forwarderAddr);
        console2.log("Consumer:", consumerAddr);
        console2.log("INDEX_NAME:", indexName);
        console2.log("AREA:", area);
        console2.log("DATE_NUM:", dateNumU);
        console2.log("VALUE_1E6:", value1e6);
        console2.logBytes32(datasetHash);
    }
}
