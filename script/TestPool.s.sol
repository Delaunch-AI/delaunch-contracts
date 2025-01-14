// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../src/LockerFactory.sol";
import "../src/DelaunchFactoryV2.sol";
import "../src/interfaces/IDelaunchFactoryV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {CLBuyContract} from "../src/utils/CLBuyer.sol";

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract ERC20Token is ERC20 {
    // Constructor to initialize the token
    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        // Mint the initial supply to the contract deployer
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    // Mint new tokens (onlyOwner is inherited from Ownable)
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Burn tokens
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
}

contract TestPool is Test {
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

    address public testTokenAddr;

    // users
    address public feeReceiver;
    address public creator;
    address public deployer;
    address public a1;
    address public a2;

    IClPoolFactory internal _pharaohFactory;
    INonfungiblePositionManager internal _positionManager;
    ILockerFactory internal _liquidityLockerFactory;

    uint256 public constant agentBeginningBal = 10000 ether;

    function run() public {
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

        _pharaohFactory = IClPoolFactory(PHARAOH_FACTORY);
        _positionManager = INonfungiblePositionManager(
            PHARAOH_POSITION_MANAGER
        );

        ERC20 testToken = new ERC20Token(
            TOKEN_NAME,
            TOKEN_SYMBOL,
            1_000_000_000
        );

        vm.startPrank(a1);
        testTokenAddr = address(testToken);

        deal(testTokenAddr, a1, 1_000_000_000 ether);

        IWETH9(WAVAX).deposit{value: 300 ether}();
        IERC20(testTokenAddr).approve(
            PHARAOH_POSITION_MANAGER,
            type(uint256).max
        );
        IERC20(WAVAX).approve(PHARAOH_POSITION_MANAGER, type(uint256).max);

        address pairAddress = _pharaohFactory.createPool(
            testTokenAddr,
            WAVAX,
            poolFee,
            sqrtPriceX96
        );

        vm.stopPrank();
    }
}
