// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TaskBoard} from "../src/TaskBoard.sol";

contract DeployScript is Script {
    function run() public {
        address ceo = vm.envAddress("CEO_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        TaskBoard taskBoard = new TaskBoard(ceo);
        console.log("TaskBoard deployed at:", address(taskBoard));

        vm.stopBroadcast();
    }
}
