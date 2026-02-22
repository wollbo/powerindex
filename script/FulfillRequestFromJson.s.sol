// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";
import { RequestRegistry } from "src/registry/RequestRegistry.sol";

contract FulfillRequestFromJson is Script {
    function run() external {
        // Required env
        address consumerAddr   = vm.envAddress("CONSUMER");
        address forwarderAddr  = vm.envAddress("FORWARDER");
        address registryAddr   = vm.envAddress("REGISTRY");
        uint256 requestId      = vm.envUint("REQUEST_ID");
        string memory path     = vm.envString("PAYLOAD_PATH");

        LocalCREForwarder forwarder = LocalCREForwarder(forwarderAddr);
        RequestRegistry registry = RequestRegistry(registryAddr);

        // Read payload
        string memory json = vm.readFile(path);

        // Support your current payload keys
        // (your workflow logs show: value1e6 + datasetHashHex)
        string memory indexName = vm.parseJsonString(json, ".indexName");
        string memory area      = vm.parseJsonString(json, ".area");
        uint256 dateNumU        = vm.parseJsonUint(json, ".dateNum");

        // value1e6 might be a string in JSON -> parseJsonString + parseInt
        string memory valueStr  = vm.parseJsonString(json, ".value1e6");
        int256 value1e6         = vm.parseInt(valueStr);

        // datasetHashHex from workflow is currently hex without 0x in logs
        // but your file may contain either with or without 0x. Normalize here:
        string memory dh = vm.parseJsonString(json, ".datasetHashHex");
        bytes32 datasetHash = _parseBytes32Flexible(dh);

        bytes32 indexId = keccak256(bytes(indexName));
        bytes32 areaId  = keccak256(bytes(area));
        uint32 dateNum  = uint32(dateNumU);

        // ABI-encoded report expected by DailyIndexConsumer:
        // (bytes32 indexId, uint32 yyyymmdd, bytes32 areaId, int256 value1e6, bytes32 datasetHash)
        bytes memory report = abi.encode(indexId, dateNum, areaId, value1e6, datasetHash);

        vm.startBroadcast();

        // 1) Mark request fulfilled in registry (for UI/audit)
        registry.markFulfilled(requestId, value1e6, datasetHash);

        // 2) Commit to consumer via forwarder
        forwarder.forward(consumerAddr, hex"", report);


        vm.stopBroadcast();

        console2.log("Fulfilled requestId:", requestId);
        console2.log("Registry:  ", registryAddr);
        console2.log("Consumer:  ", consumerAddr);
        console2.log("Forwarder: ", forwarderAddr);
        console2.log("indexName: ", indexName);
        console2.log("area:      ", area);
        console2.log("dateNum:   ", dateNumU);
        console2.log("value1e6:  ", value1e6);
        console2.logBytes32(datasetHash);
        console2.log("payload:   ", path);
    }

    function _parseBytes32Flexible(string memory s) internal pure returns (bytes32) {
        bytes memory b = bytes(s);
        if (b.length == 66 && b[0] == "0" && (b[1] == "x" || b[1] == "X")) {
            // "0x" + 64 hex
            return bytes32(vm.parseBytes32(s));
        }
        if (b.length == 64) {
            // 64 hex without 0x -> add 0x
            return bytes32(vm.parseBytes32(string.concat("0x", s)));
        }
        revert("datasetHashHex must be 0x+64hex or 64hex");
    }
}
