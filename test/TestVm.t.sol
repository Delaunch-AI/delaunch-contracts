// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/LockerFactory.sol";
import "../src/DelaunchFactoryV2.sol";
import "../src/interfaces/IDelaunchFactoryV2.sol";

import {CLBuyContract} from "../src/utils/CLBuyer.sol";

contract DlTestVm is Test {
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

    }

    function test_deployToken() public view {
        //token in bonding curve contract

        assertEq(testToken.name(), TOKEN_NAME);
        assertEq(testToken.symbol(), TOKEN_SYMBOL);
        assertEq(testToken.factory(), address(delaunchFactory));
        assertEq(testToken.deployer(), address(delaunchFactory));
        assertEq(testToken.creator(), creator);
        assertEq(testToken.curveComplete(), false);

        assertEq(
            testToken.balanceOf(address(delaunchFactory)),
            1000_000_000 ether
        );

        assertEq(delaunchFactory.allTokensLength(), 1);
        assertEq(delaunchFactory.allTokens(0), testTokenAddr);
        assertEq(delaunchFactory.tokens(testTokenAddr).avaxReserve, 0);
        assertEq(delaunchFactory.tokens(testTokenAddr).creator, creator);
        assertEq(delaunchFactory.tokens(testTokenAddr).pairAddress, address(0));
        assertEq(
            delaunchFactory.tokens(testTokenAddr).lockerAddress,
            address(0)
        );
    }

    function test_launch() public {
        assertEq(a1.balance, agentBeginningBal);

        vm.startPrank(a1);
        (
            uint256 amountUsed,
            uint256 amountOut,
            address pairAddress,
            uint256 tokenId,
            address lockerAddress
        ) = delaunchFactory.buy{value: 253 ether}(testTokenAddr, 0);

        // fee receiver receives 10 avax launch fee + 2.5 trading fees
        assertEq(feeReceiver.balance, 12500000000000000000);

        assertEq(IERC20(WAVAX).balanceOf(pairAddress), 239992956277939196409);
        assertEq(testToken.balanceOf(pairAddress), 199999999999999999999999212);

        assertEq(
            amountUsed / (10 ** 18),
            delaunchFactory.clPoolConfig().targetPoolAvaxBalance / (10 ** 18)
        );

        assertEq(testToken.balanceOf(a1), 800_000_000 ether);

        assert(testToken.curveComplete());
        assert(pairAddress != address(0));
        assert(tokenId != 0);

        assertEq(delaunchFactory.tokens(testTokenAddr).hasLaunched, true);
        assertEq(
            delaunchFactory.tokens(testTokenAddr).pairAddress,
            pairAddress
        );
        assertEq(
            delaunchFactory.tokens(testTokenAddr).lockerAddress,
            lockerAddress
        );

        vm.stopPrank();
    }

    function test_slippage() public {
        vm.startPrank(a1);

        testToken.approve(address(delaunchFactory), type(uint256).max);

        uint256 tokenAmountOut = delaunchFactory.getBuyAmountOut(
            testTokenAddr,
            (220 ether * 99) / 100 //account 1% for fees
        );

        vm.expectRevert();
        delaunchFactory.buy{value: 220 ether}(
            testTokenAddr,
            tokenAmountOut + 100 ether
        );

        //buy with 1% slippage
        delaunchFactory.buy{value: 220 ether}(
            testTokenAddr,
            (tokenAmountOut * 99) / 100
        );

        uint256 avaxAmountOut = delaunchFactory.getSellAmountOut(
            testTokenAddr,
            IERC20(testTokenAddr).balanceOf(a1)
        );

        //sell with 1% slippage
        delaunchFactory.sell(
            testTokenAddr,
            IERC20(testTokenAddr).balanceOf(a1),
            (avaxAmountOut * 99) / 100
        );

        vm.stopPrank();
    }

    function test_deprecate() public {
        (bytes32 salt, ) = delaunchFactory.generateSalt(
            "haha",
            "hehe",
            creator
        );

        delaunchFactory.createToken(
            "haha",
            "hehe",
            creator,
            METADATA_URI,
            salt
        );

        vm.prank(deployer);
        delaunchFactory.setDeprecated(true);

        (bytes32 salt2, ) = delaunchFactory.generateSalt(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator
        );

        vm.expectRevert();
        delaunchFactory.createToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator,
            METADATA_URI,
            salt2
        );
    }

    function test_ownership() public {
        vm.startPrank(a1);

        vm.expectRevert();
        delaunchFactory.changeFeeReceiver(a2);

        vm.expectRevert();
        delaunchFactory.changeCurveLaunchFee(12 ether);

        vm.expectRevert();
        delaunchFactory.changeCurveTradingFee(240);

        vm.expectRevert();
        delaunchFactory.setIsPaused(true);

        vm.expectRevert();
        delaunchFactory.setDeprecated(true);

        vm.stopPrank();

        vm.startPrank(deployer);

        delaunchFactory.changeFeeReceiver(a2);
        assertEq(delaunchFactory.getFeeReceiver(), a2);

        delaunchFactory.changeCurveLaunchFee(12 ether);
        assertEq(delaunchFactory.curveConfig().launchFee, 12 ether);

        delaunchFactory.changeCurveTradingFee(240);
        assertEq(delaunchFactory.curveConfig().curveFee, 240);

        delaunchFactory.setIsPaused(true);
        assertEq(delaunchFactory.isPaused(), true);

        delaunchFactory.setDeprecated(true);

        (bytes32 salt, ) = delaunchFactory.generateSalt(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator
        );
        vm.expectRevert();
        delaunchFactory.createToken(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            creator,
            METADATA_URI,
            salt
        );
        vm.stopPrank();
    }

    function test_CollectFeesOnLPlocker() public {
        vm.startPrank(a2);
        (, , , uint256 tokenId, ) = delaunchFactory.buy{value: 900 ether}(
            testTokenAddr,
            1
        );

        assert(tokenId != 0);

        // Simulate some trading fees
        CLBuyContract clBuy = new CLBuyContract(PHARAOH_ROUTER, WAVAX);

        clBuy.depositWavax{value: 1000 ether}();
        clBuy.buySingle(testTokenAddr, 1000 ether, 0, 10000);

        vm.stopPrank();

        // Get locker address
        IERC721 positionManager = IERC721(PHARAOH_POSITION_MANAGER);
        // either fee receiver or creator can call
        vm.startPrank(creator);

        address payable lockerAddress = payable(
            positionManager.ownerOf(tokenId)
        );

        // Collect fees
        LpLocker locker = LpLocker(lockerAddress);

        assertEq(IERC20(WAVAX).balanceOf(creator), 0);
        assertEq(testToken.balanceOf(creator), 0);

        assertEq(IERC20(WAVAX).balanceOf(feeReceiver), 0);
        assertEq(testToken.balanceOf(feeReceiver), 0);

        console.log("CLAIM");

        (uint256 creatorFee0, uint256 creatorFee1) = locker.collectFees(
            creator
        );

        console.log("creator fee 0:", creatorFee0);
        assertEq(creatorFee1, 5999999999999999999);

        assertEq(IERC20(WAVAX).balanceOf(creator), 6 ether);
        console.log("test token balance creator", testToken.balanceOf(creator));

        //3.9 ether
        assertEq(IERC20(WAVAX).balanceOf(feeReceiver), 3999999999999999999);

        console.log(
            "test token balance feeReceiver",
            testToken.balanceOf(feeReceiver)
        );

        vm.stopPrank();
    }

    function test_claimLP() public {
        vm.startPrank(a1);
        (, , , uint256 tokenId, ) = delaunchFactory.buy{value: 900 ether}(
            testTokenAddr,
            1
        );

        IERC721 positionManager = IERC721(PHARAOH_POSITION_MANAGER);
        address payable lockerAddress = payable(
            positionManager.ownerOf(tokenId)
        );

        // Collect LP
        LpLocker locker = LpLocker(lockerAddress);

        // creator / others not allowed to collect
        vm.expectRevert();
        locker.release();

        vm.stopPrank();

        vm.warp(block.timestamp + 15_552_000);

        assertEq(positionManager.balanceOf(feeReceiver), 0);

        vm.prank(feeReceiver);
        locker.release();

        assertEq(positionManager.balanceOf(feeReceiver), 1);
    }

    function test_launchWithBuyDirect() public {
        assertEq(a1.balance, agentBeginningBal);

        vm.startPrank(a1);
        (bytes32 salt, ) = delaunchFactory.generateSalt(
            "haha",
            "hehe",
            creator
        );

        DelaunchTokenV2 testToken2 = delaunchFactory.createToken{
            value: 260 ether
        }("haha", "hehe", creator, METADATA_URI, salt);

        address testTokenAddr2 = address(testToken2);

        assert(delaunchFactory.tokens(testTokenAddr2).hasLaunched);
        assert(testToken2.curveComplete());

        address lockerAddress = delaunchFactory
            .tokens(testTokenAddr2)
            .lockerAddress;

        address pairAddress = delaunchFactory
            .tokens(testTokenAddr2)
            .pairAddress;

        assert(pairAddress != address(0));
        assert(lockerAddress != address(0));

        // fee receiver receives 10 avax launch fee + 2.5 trading fees
        assertEq(feeReceiver.balance, 12500000000000000000);

        assertEq(IERC20(WAVAX).balanceOf(pairAddress), 239992956277939196409);
        assertEq(
            testToken2.balanceOf(pairAddress),
            199999999999999999999999212
        );

        assertEq(testToken2.balanceOf(a1), 800_000_000 ether);

        vm.stopPrank();
    }

    function test_launchWithBuy() public {
        assertEq(a1.balance, agentBeginningBal);

        vm.startPrank(a1);
        (bytes32 salt, ) = delaunchFactory.generateSalt(
            "haha",
            "hehe",
            creator
        );

        DelaunchTokenV2 testToken2 = delaunchFactory.createToken{
            value: 240 ether
        }("haha", "hehe", creator, METADATA_URI, salt);

        address testTokenAddr2 = address(testToken2);

        assertEq(
            delaunchFactory.tokens(testTokenAddr2).avaxReserve,
            (240 ether * (10000 - delaunchFactory.curveConfig().curveFee)) /
                10000
        );

        assertEq(testToken2.balanceOf(a1), 779907686000000000000000000);

        assertEq(
            feeReceiver.balance,
            (240 ether * delaunchFactory.curveConfig().curveFee) / 10000
        );

        (
            uint256 amountUsed,
            uint256 amountOut,
            address pairAddress,
            uint256 tokenId,
            address lockerAddress
        ) = delaunchFactory.buy{value: 500 ether}(testTokenAddr2, 0);

        // fee receiver receives 10 avax launch fee + 2.5 trading fees + some dust
        assertEq(feeReceiver.balance, 12524000000000000000);
        //
        address pairAddress2 = delaunchFactory
            .tokens(testTokenAddr2)
            .pairAddress;
        address lockerAddress2 = delaunchFactory
            .tokens(testTokenAddr2)
            .lockerAddress;

        assertEq(IERC20(WAVAX).balanceOf(pairAddress), 239992956277939196409);
        assertEq(
            testToken2.balanceOf(pairAddress),
            199999999999999999999999212
        );

        assertEq(testToken2.balanceOf(a1), 799999999000000000000000000);

        assert(testToken2.curveComplete());
        assert(pairAddress != address(0));
        assert(tokenId != 0);

        assertEq(delaunchFactory.tokens(testTokenAddr2).hasLaunched, true);
        assertEq(
            delaunchFactory.tokens(testTokenAddr2).pairAddress,
            // pairAddress2,
            pairAddress
        );
        assertEq(
            delaunchFactory.tokens(testTokenAddr2).lockerAddress,
            // lockerAddress2,
            lockerAddress
        );

        vm.stopPrank();
    }

    function test_launchWithPoolAttacker() public {
        IClPoolFactory _pharaohFactory = IClPoolFactory(PHARAOH_FACTORY);

        vm.startPrank(a1);

        assertEq(
            delaunchFactory.tokens(testTokenAddr).newTokenAddress,
            address(0)
        );

        //create a pool with random sqrtratio to pose as attacker
        _pharaohFactory.createPool(
            testTokenAddr,
            WAVAX,
            poolFee,
            66788829993635471478925502
        );

        delaunchFactory.buy{value: 500 ether}(testTokenAddr, 0);

        //it should detour and create a new token and insert into pool
        address newTokenAddr = delaunchFactory
            .tokens(testTokenAddr)
            .newTokenAddress;

        console.log("new token", newTokenAddr);
        assert(newTokenAddr != address(0));

        assertFalse(IDelaunchTokenV2(testTokenAddr).curveComplete());
        assertTrue(IDelaunchTokenV2(newTokenAddr).curveComplete());

        uint256 oldTokenBalance = IERC20(testTokenAddr).balanceOf(a1);

        assertEq(IERC20(newTokenAddr).balanceOf(a1), 0);

        assertFalse(IDelaunchTokenV2(testTokenAddr).curveComplete());
        assert(IDelaunchTokenV2(newTokenAddr).curveComplete());

        //claim new tokens with old tokens
        IERC20(testTokenAddr).approve(
            address(delaunchFactory),
            type(uint256).max
        );
        delaunchFactory.claimNewTokens(testTokenAddr, oldTokenBalance);

        assertEq(IERC20(newTokenAddr).balanceOf(a1), oldTokenBalance);

        vm.stopPrank();
    }
}
