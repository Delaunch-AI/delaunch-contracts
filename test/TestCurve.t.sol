// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/LockerFactory.sol";
import "../src/DelaunchFactoryV2.sol";
import "../src/interfaces/IDelaunchFactoryV2.sol";

contract DlCurveBuySellTestVm is Test {
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
    uint64 public constant lpLockPeriod = 180 days;

    // CurveConfig
    uint256 public constant poolShare = 8000; // 80%
    uint256 public constant reserveRatio = 500000; // 50%
    uint256 public constant curveFee = 100; // 1%
    uint256 public constant launchFee = 10 ether;

    IDelaunchFactoryV2 public delaunchFactory;
    DelaunchTokenV2 public testToken;
    address public testTokenAddr;

    // users
    address public feeReceiver;
    address public creator;
    address public deployer;
    address public a1;
    address public a2;

    uint256 public constant agentBeginningBal = 10000 ether;

    function setUp() public {
        // SETUP AGENTS & FORK MAINNET
        vm.createSelectFork(vm.envString("AVALANCHE_RPC"));
        a1 = makeAddr("a1");
        a2 = makeAddr("a2");
        creator = makeAddr("creator");
        feeReceiver = makeAddr("feeReceiver");
        deployer = makeAddr("deployer");

        vm.deal(a1, agentBeginningBal);
        vm.deal(a2, agentBeginningBal);
        vm.deal(deployer, 100 ether);

        //DEPLOY CONTRACTS
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

        // console.log("A1 address:", a1);
        // console.log("A2 address:", a2);
        // console.log("creator address:", creator);
        // console.log("Deployer address:", deployer);
        // console.log("LockerFactory deployed at:", address(lockerFactory));
        // console.log("BondingFactory deployed at:", address(delaunchFactory));
    }

    function test_curve_values() public {
        vm.startPrank(a1);

        (uint256 amount1Used, uint256 amountOut, , , ) = delaunchFactory.buy{
            value: avaxBin1
        }(testTokenAddr, 0);



        console.log("---");
        console.log("1st avax input", avaxBin1 / (10 ** 18));
        console.log(
            "actual used avax to buy token (exclude trading fee 1%)",
            amount1Used / (10 ** 18)
        );
        console.log("token bought", amountOut / (10 ** 18));
        console.log(
            "DelaunchFactory contract balance:",
            testToken.balanceOf(address(delaunchFactory)) / (10 ** 18)
        );

        console.log("---");

        console.log(
            "contract avax balance:",
            address(delaunchFactory).balance / (10 ** 18)
        );

        console.log("a1 token balance:", testToken.balanceOf(a1) / (10 ** 18));

        console.log("_____________________________");

        uint256 avaxBin2 = 125 ether; // (253 ether includes trading fee to complete curve)
        (uint256 amount2Used, uint256 amountOut2, , , ) = delaunchFactory.buy{
            value: avaxBin2
        }(testTokenAddr, 0);

        console.log("---");
        console.log("2nd avax input", avaxBin2 / (10 ** 18));
        console.log(
            "actual used avax to buy token (exclude trading fee 1%)",
            amount2Used / (10 ** 18)
        );
        console.log("token bought", amountOut2 / (10 ** 18));
        console.log(
            "DelaunchFactory contract balance:",
            testToken.balanceOf(address(delaunchFactory)) / (10 ** 18)
        );

        console.log("---");

        console.log(
            "contract avax balance:",
            address(delaunchFactory).balance / (10 ** 18)
        );

        console.log("a1 token balance:", testToken.balanceOf(a1) / (10 ** 18));

        console.log("_____________________________");


        console.log("_____________________________");

        console.log(
            "Contract AVAX balance AFTER BUY",
            address(delaunchFactory).balance / (10 ** 18)
        );

        console.log("A1 avax balance AFTER SELL", a1.balance / (10 ** 18));

        vm.stopPrank();
    }
}
