// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { DailyIndexConsumer } from "src/DailyIndexConsumer.sol";
import { LocalCREForwarder } from "src/forwarders/LocalCREForwarder.sol";

contract DeployConsumer is Script {
    function run() external returns (DailyIndexConsumer consumer, LocalCREForwarder forwarder) {
        vm.startBroadcast();

        forwarder = new LocalCREForwarder();
        consumer = new DailyIndexConsumer(address(forwarder));
        
        forwarder.setAllowedSender(msg.sender, true);

        vm.stopBroadcast();

        // write to disk (make sure foundry.toml has fs_permissions allowing deployments/)
        vm.writeFile("deployments/consumer.txt", vm.toString(address(consumer)));
        vm.writeFile("deployments/forwarder.txt", vm.toString(address(forwarder)));

        console2.log("Consumer:", address(consumer));
        console2.log("Forwarder:", address(forwarder));
    }
}

