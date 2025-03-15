// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../interfaces/IUniswapV3.sol";
import "../interfaces/IWNATIVE.sol";
import "../token/DelaunchTokenV2.sol";
import "../interfaces/IDelaunchTokenV2.sol";
import "../DelaunchCurveFormula.sol";

interface IDelaunchFactoryV2 is IERC721Receiver {
    function isPaused() external view returns (bool);
    function deprecated() external view returns (bool);
    function feeReceiver() external view returns (address);
    function tokens(address token) external view returns (Token memory);
    function curveConfig() external view returns (CurveConfig memory);
    function clPoolConfig() external view returns (ClPoolConfig memory);

    function allTokens(uint256 index) external view returns (address);

    function createToken(
        string calldata name_,
        string calldata symbol_,
        address creator_,
        string calldata metadataUri,
        bytes32 salt_
    ) external payable returns (DelaunchTokenV2 token);

    function predictToken(
        string calldata name,
        string calldata symbol,
        address creator,
        bytes32 salt
    ) external view returns (address);

    function generateSalt(
        string calldata name,
        string calldata symbol,
        address creator
    ) external view returns (bytes32 salt, address token);

    // Circulating Supply
    function getCirculatingSupply(
        address token0
    ) external view returns (uint256);

    function getBuyAmountOut(
        address token0,
        uint256 amountIn
    ) external view returns (uint256);

    function getSellAmountOut(
        address token0,
        uint256 amountIn
    ) external view returns (uint256);

    function buy(
        address token0,
        uint256 amountOutMin
    )
        external
        payable
        returns (
            uint256 value,
            uint256 amountOut,
            address pairAddress,
            uint256 tokenId,
            address lockerAddress
        );

    function sell(
        address token0,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (uint256 finalAmountOut);

    function claimNewTokens(address originalToken, uint256 amountIn) external;

    event TokenClaimed(
        address indexed originalToken,
        address indexed newToken,
        address indexed sender,
        uint256 amountIn
    );

    event TokenCreated(
        address indexed sender,
        address indexed token,
        address indexed creator,
        string metadataUri
    );

    event Swap(
        address indexed token,
        address indexed sender,
        uint256 amount0In,
        uint256 amount0Out,
        uint256 amount1In,
        uint256 amount1Out
    );

    event CurveCompleted(
        address indexed token,
        address indexed newToken,
        address indexed pairAddress,
        address lockerAddress
    );

    struct Token {
        address creator;
        uint256 avaxReserve;
        bool hasLaunched;
        address pairAddress;
        address lockerAddress;
        address newTokenAddress;
    }

    struct ClPoolConfig {
        int24 tickSpacing;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint256 targetPoolAvaxBalance;
        uint8 creatorFeeCut;
        uint24 poolFee;
        uint64 lpLockPeriod;
    }

    struct CurveConfig {
        uint256 poolShare;
        uint256 reserveRatio;
        uint256 curveFee;
        uint256 launchFee;
    }

    function allTokensLength() external view returns (uint256);
    function getFeeReceiver() external view returns (address);

    // Owner
    function changeFeeReceiver(address feeReceiver_) external;
    function changeCurveTradingFee(uint24 newFee_) external;
    function changeCurveLaunchFee(uint256 newFee_) external;
    function setIsPaused(bool isPaused_) external;
    function setDeprecated(bool deprecated_) external;
}
