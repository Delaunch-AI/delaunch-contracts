// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {LockerFactory} from "../src/LockerFactory.sol";
import {IClPoolFactory} from "../src/interfaces/IUniswapV3.sol";
import "../src/interfaces/IDelaunchFactoryV2.sol";
import "../src/DelaunchFactoryV2.sol";

contract DeployScript is Script {
    // Pharaoh Exchange Addresses on Avalanche Mainnet
    address constant PHARAOH_FACTORY =
        0xAAA32926fcE6bE95ea2c51cB4Fcb60836D320C42;
    address constant PHARAOH_POSITION_MANAGER =
        0xAAA78E8C4241990B4ce159E105dA08129345946A;
    address constant PHARAOH_ROUTER =
        0xAAAE99091Fbb28D400029052821653C1C752483B;
    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    //token info
    string constant TOKEN_NAME = "TEST TOKEN";
    string constant TOKEN_SYMBOL = "TEST";
    string constant METADATA_URI = "";

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
    uint256 public constant poolShare = 8000; // 80%
    uint256 public constant reserveRatio = 500000; // 50%
    uint256 public constant curveFee = 100; // 1%
    uint256 public constant launchFee = 10 ether;

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

        LockerFactory lockerFactory = new LockerFactory();

        IDelaunchFactoryV2.CurveConfig memory curveConfig = IDelaunchFactoryV2
            .CurveConfig(poolShare, reserveRatio, curveFee, launchFee);

        IDelaunchFactoryV2.ClPoolConfig memory clPoolConfig = IDelaunchFactoryV2
            .ClPoolConfig(
                tickSpacing,
                tickLower,
                tickUpper,
                sqrtPriceX96,
                targetPoolAvaxBalance,
                creatorFeeCut,
                poolFee,
                lpLockPeriod
            );

        DelaunchFactoryV2 factory = new DelaunchFactoryV2(
            // EcoSystem
            PHARAOH_FACTORY,
            PHARAOH_POSITION_MANAGER,
            address(lockerFactory),
            // roles
            deployer, //owner
            feeReceiver,
            // config
            clPoolConfig,
            curveConfig
        );

        delaunchFactory = IDelaunchFactoryV2(address(factory));

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

        console.log("LockerFactory deployed at:", address(lockerFactory));
        console.log("DelaunchFactory deployed at:", address(factory));
        console.log("TestToken deployed at:", testTokenAddr);

        vm.stopBroadcast();
    }
}
