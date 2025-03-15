// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LockerFactory} from "../src/LockerFactory.sol";
import {IClPoolFactory} from "../src/interfaces/IUniswapV3.sol";
import "../src/interfaces/IDelaunchFactoryV2.sol";
import "../src/DelaunchFactoryV2.sol";

contract DeployTokenScript is Script {
    //token info
    string constant TOKEN_NAME = "TEST TOKEN";
    string constant TOKEN_SYMBOL = "TEST";
    string constant METADATA_URI = "";

    address delaunchFactoryAddr = 0x58e028024352a6e1E2fC0c41Fb7994f26189dC6a;
    IDelaunchFactoryV2 public delaunchFactory;
    DelaunchTokenV2 public testToken;
    address public testTokenAddr;

    address public creator;
    address public feeReceiver;
    address public deployer;

    function run() public {
        creator = vm.envAddress("CREATOR_ADDRESS");
        feeReceiver = vm.envAddress("FEE_RECEIVER_ADDRESS");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        delaunchFactory = IDelaunchFactoryV2(delaunchFactoryAddr);

        // DEPLOY TEST TOKEN
        (bytes32 salt, ) = delaunchFactory.generateSalt(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator
        );

        testToken = delaunchFactory.createToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator,
            METADATA_URI,
            salt
        );

        testTokenAddr = address(testToken);

        console.log("TestToken deployed at:", testTokenAddr);

        vm.stopBroadcast();
    }
}
