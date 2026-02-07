// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DailyIndexConsumer.sol";

contract RelayFromJson is Script {
    function run() external {
        address consumerAddr = vm.envAddress("CONSUMER");
        string memory path = vm.envString("PAYLOAD_PATH"); // path to latest.json
        DailyIndexConsumer consumer = DailyIndexConsumer(consumerAddr);

        string memory json = vm.readFile(path);

        string memory indexName = vm.parseJsonString(json, ".indexName");
        string memory area = vm.parseJsonString(json, ".area");
        uint256 dateNumU = vm.parseJsonUint(json, ".dateNum");
        uint256 value1e6U = vm.parseJsonUint(json, ".value1e6");
        string memory preimage = vm.parseJsonString(json, ".preimage");

        bytes32 indexId = keccak256(bytes(indexName));
        bytes32 areaId  = keccak256(bytes(area));
        uint32 dateNum  = uint32(dateNumU);
        uint256 value1e6 = value1e6U;

        // Commit to the canonical preimage
        bytes32 dataHash = keccak256(abi.encodePacked(preimage));

        bytes memory report = abi.encode(indexId, dateNum, areaId, value1e6, dataHash);

        vm.startBroadcast();
        consumer.onReport(hex"", report);
        vm.stopBroadcast();

        console2.log("Relayed report to:", consumerAddr);
        console2.log("PAYLOAD_PATH:", path);
    }
}
