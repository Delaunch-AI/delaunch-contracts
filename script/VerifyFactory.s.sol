// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {DelaunchFactoryV2} from "../src/DelaunchFactoryV2.sol";
import {IDelaunchFactoryV2} from "../src/interfaces/IDelaunchFactoryV2.sol";

contract VerifyScript is Script {
    // Pharaoh Exchange Addresses on Avalanche Mainnet
    address constant PHARAOH_FACTORY =
        0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42;
    address constant PHARAOH_POSITION_MANAGER =
        0xAAA78E8C4241990B4ce159E105dA08129345946A;
    address constant PHARAOH_ROUTER =
        0xAAAE99091Fbb28D400029052821653C1C752483B;
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    // CLPoolConfig
    int24 public constant tickSpacing = 200;
    int24 public constant tickLower = -887200;
    int24 public constant tickUpper = 887200;
    uint160 public constant sqrtPriceX96 = 86788829993635471478925502;
    uint256 public constant targetPoolAvaxBalance = 250 ether;
    uint8 public constant creatorFeeCut = 60;
    uint24 public constant poolFee = 10_000;
    uint64 public constant lpLockPeriod = 1 minutes;

    // CurveConfig
    uint256 public constant poolShare = 8000;
    uint256 public constant reserveRatio = 500000;
    uint256 public constant curveFee = 100;
    uint256 public constant launchFee = 10 ether;

    //FILL THESE
    address public delaunchFactoryAddress =
        0xAAAE99091Fbb28D400029052821653C1C752483B;

    address public lockerFactoryAddress =
        0xAAAE99091Fbb28D400029052821653C1C752483B;

    address public feeReceiver;
    address public deployer;

    function run() public {
        feeReceiver = vm.envAddress("FEE_RECEIVER_ADDRESS");
        deployer = vm.envAddress("DEPLOYER_ADDRESS");
        console.log("\n=== Contract Addresses ===");
        console.log("DelaunchFactory:", delaunchFactoryAddress);
        console.log("LockerFactory:", lockerFactoryAddress);

        // Create the constructor arguments array
        string[] memory args = new string[](7);
        args[0] = vm.toString(PHARAOH_FACTORY);
        args[1] = vm.toString(PHARAOH_POSITION_MANAGER);
        args[2] = vm.toString(lockerFactoryAddress);
        args[3] = vm.toString(deployer);
        args[4] = vm.toString(feeReceiver);

        // Format CLPoolConfig struct fields
        args[5] = string.concat(
            vm.toString(tickSpacing),
            ":",
            vm.toString(tickLower),
            ":",
            vm.toString(tickUpper),
            ":",
            vm.toString(sqrtPriceX96),
            ":",
            vm.toString(targetPoolAvaxBalance),
            ":",
            vm.toString(creatorFeeCut),
            ":",
            vm.toString(poolFee),
            ":",
            vm.toString(lpLockPeriod)
        );

        // Format CurveConfig struct fields
        args[6] = string.concat(
            vm.toString(poolShare),
            ":",
            vm.toString(reserveRatio),
            ":",
            vm.toString(curveFee),
            ":",
            vm.toString(launchFee)
        );

        // Build constructor arguments string
        string memory constructorArgs = "[";
        for (uint i = 0; i < args.length; i++) {
            if (i > 0) constructorArgs = string.concat(constructorArgs, ",");
            constructorArgs = string.concat(constructorArgs, '"', args[i], '"');
        }
        constructorArgs = string.concat(constructorArgs, "]");

        string memory verifyCommand = string.concat(
            "forge verify-contract ",
            vm.toString(delaunchFactoryAddress),
            " src/DelaunchFactoryV2.sol:DelaunchFactoryV2",
            " --constructor-args ",
            constructorArgs,
            " --compiler-version 0.8.20",
            " --optimizer",
            " --optimizer-runs 200",
            " --via-ir",
            " --chain avalanche",
            " --watch"
        );

        console.log("\nVerification command:");
        console.log(verifyCommand);

        console.log("\nRequired environment variables:");
        console.log("export ETHERSCAN_API_KEY=your_snowtrace_api_key");
        console.log(
            "export DELAUNCH_FACTORY_ADDRESS=deployed_delaunch_factory_address"
        );
        console.log(
            "export LOCKER_FACTORY_ADDRESS=deployed_locker_factory_address"
        );
    }
}
