// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {DailyIndexConsumer} from "src/DailyIndexConsumer.sol";
import {LocalCREForwarder} from "src/forwarders/LocalCREForwarder.sol";
import {RequestRegistry} from "src/registry/RequestRegistry.sol";
import {NorthpoleOptionFactory} from "src/market/NorthpoleOptionFactory.sol";

contract DeployConsumer is Script {
    function run()
        external
        returns (
            DailyIndexConsumer consumer,
            LocalCREForwarder forwarder,
            RequestRegistry registry,
            NorthpoleOptionFactory factory
        )
    {
        vm.startBroadcast();

        // 1) Forwarder
        forwarder = new LocalCREForwarder();

        // 2) Consumer wired to forwarder
        consumer = new DailyIndexConsumer(address(forwarder));

        // 3) Registry wired to consumer; fulfiller = deployer EOA for local
        // Otherwise, pass a dedicated fulfiller address via env.
        address fulfiller = msg.sender;
        registry = new RequestRegistry(fulfiller, address(consumer));

        // 4) Allow deployer EOA to forward reports locally
        forwarder.setAllowedSender(msg.sender, true);

        // 5) Deploy factory contract
        factory = new NorthpoleOptionFactory();

        vm.stopBroadcast();

        console2.log("Forwarder:", address(forwarder));
        console2.log("Consumer:  ", address(consumer));
        console2.log("Registry:  ", address(registry));
        console2.log("Factory:  ", address(factory));

        // Persist addresses
        // Make sure deployments/ exists in repo root
        vm.writeFile("deployments/forwarder.txt", vm.toString(address(forwarder)));
        vm.writeFile("deployments/consumer.txt", vm.toString(address(consumer)));
        vm.writeFile("deployments/registry.txt", vm.toString(address(registry)));
        vm.writeFile("deployments/factory.txt", vm.toString(address(factory)));
    }
}
