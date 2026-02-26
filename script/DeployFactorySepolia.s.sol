// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {NorthpoleOptionFactory} from "src/market/NorthpoleOptionFactory.sol";

contract DeployFactorySepolia is Script {
    function run() external returns (NorthpoleOptionFactory factory) {
        uint256 pk = vm.envUint("PK"); // expects 0x... hex
        vm.startBroadcast(pk);

        factory = new NorthpoleOptionFactory();

        vm.stopBroadcast();

        console2.log("Factory:", address(factory));

        // optional: persist
        vm.writeFile("deployments/factory.sepolia.txt", vm.toString(address(factory)));
    }
}
