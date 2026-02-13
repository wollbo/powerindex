// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";

contract RelayFromJson is Script {
    function run() external {
        address consumerAddr = vm.envAddress("CONSUMER");
        address forwarderAddr = vm.envAddress("FORWARDER");
        string memory path = vm.envString("PAYLOAD_PATH"); // path to latest.json

        LocalCREForwarder forwarder = LocalCREForwarder(forwarderAddr);

        string memory json = vm.readFile(path);

        string memory indexName = vm.parseJsonString(json, ".indexName");
        string memory area = vm.parseJsonString(json, ".area");
        uint256 dateNumU = vm.parseJsonUint(json, ".dateNum");

        // value1e6 is stored as a JSON string in payloads -> parse string then int
        string memory valueStr = vm.parseJsonString(json, ".value1e6");
        int256 value1e6 = vm.parseInt(valueStr);

        string memory datasetHashHex = vm.parseJsonString(json, ".datasetHashHex");
        bytes32 datasetHash = bytes32(vm.parseUint(string.concat("0x", datasetHashHex)));


        bytes32 indexId = keccak256(bytes(indexName));
        bytes32 areaId  = keccak256(bytes(area));
        uint32 dateNum  = uint32(dateNumU);

        bytes memory report = abi.encode(indexId, dateNum, areaId, value1e6, datasetHash);

        vm.startBroadcast();
        forwarder.forward(consumerAddr, hex"", report);
        vm.stopBroadcast();

        console2.log("Relayed via forwarder:", forwarderAddr);
        console2.log("To consumer:", consumerAddr);
        console2.log("PAYLOAD_PATH:", path);
        console2.log("datasetHash:");
        console2.logBytes32(datasetHash);
        console2.log("value1e6:", value1e6);
    }
}
