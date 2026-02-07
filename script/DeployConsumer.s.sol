// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DailyIndexConsumer.sol";

contract DeployConsumer is Script {
    function run() external returns (DailyIndexConsumer consumer) {
        vm.startBroadcast();
        consumer = new DailyIndexConsumer();
        vm.stopBroadcast();

        console2.log("DailyIndexConsumer deployed at:", address(consumer));

        // Write address to file
        string memory out = vm.toString(address(consumer));
        vm.writeFile("deployments/consumer.txt", out);
    }
}