// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {DailyIndexConsumer} from "src/DailyIndexConsumer.sol";

contract DeployConsumerSepolia is Script {
    function run() external returns (DailyIndexConsumer consumer) {
        uint256 pk = vm.envUint("PK");
        address deployer = vm.addr(pk);
        address initialForwarder = deployer;

        vm.startBroadcast(pk);

        consumer = new DailyIndexConsumer(initialForwarder);

        vm.stopBroadcast();

        console2.log("Deployer:          ", deployer);
        console2.log("DailyIndexConsumer:", address(consumer));
        console2.log("Initial forwarder: ", initialForwarder);

        vm.createDir("deployments", true);
        vm.writeFile("deployments/consumer.txt", vm.toString(address(consumer)));
    }
}
