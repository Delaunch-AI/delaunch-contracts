// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Bytes32AddressLib} from "./libraries/Bytes32AddressLib.sol";
import {INonfungiblePositionManager, ILocker, IClPoolFactory, ILockerFactory} from "./interfaces/IUniswapV3.sol";
import "./interfaces/IWNATIVE.sol";
import "./token/DelaunchTokenV2.sol";
import "./interfaces/IDelaunchTokenV2.sol";
import "./DelaunchCurveFormula.sol";
import "./interfaces/IDelaunchFactoryV2.sol";

contract DelaunchFactoryV2 is
    Ownable,
    ReentrancyGuard,
    IERC721Receiver,
    DelaunchCurveFormula,
    IDelaunchFactoryV2
{
    using Bytes32AddressLib for bytes32;

    // Core contracts & addresses
    address internal _wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    IClPoolFactory internal _pharaohFactory;
    INonfungiblePositionManager internal _positionManager;
    ILockerFactory internal _liquidityLockerFactory;

    // Configs
    ClPoolConfig internal _clPoolConfig;
    CurveConfig internal _curveConfig;

    uint256 internal constant _tokenBaseSupply = 1_000_000_000 ether;

    // Ecosystem Info
    bool public isPaused;
    bool public deprecated;
    address public feeReceiver;

    address[] public allTokens;
    mapping(address => Token) internal _tokens;

    constructor(
        // EcoSystem
        address pharaohFactory_,
        address positionManager_,
        address liquidityLocker_,
        // Roles
        address owner_,
        address feeReceiver_,
        // Config
        ClPoolConfig memory clPoolConfig_,
        CurveConfig memory curveConfig_
    )
        Ownable(owner_)
        DelaunchCurveFormula(
            clPoolConfig_.targetPoolAvaxBalance,
            (_tokenBaseSupply * curveConfig_.poolShare) / 10000,
            curveConfig_.reserveRatio
        )
    {
        _pharaohFactory = IClPoolFactory(pharaohFactory_);
        _positionManager = INonfungiblePositionManager(positionManager_);
        _liquidityLockerFactory = ILockerFactory(liquidityLocker_);

        _curveConfig = curveConfig_;
        _clPoolConfig = clPoolConfig_;

        feeReceiver = feeReceiver_;

        deprecated = false;
        isPaused = false;

        IERC20(_wavax).approve(positionManager_, type(uint256).max);
    }

    function createToken(
        string memory name_,
        string memory symbol_,
        address creator_,
        string calldata metadataUri,
        bytes32 salt_
    ) external payable returns (DelaunchTokenV2 token) {
        require(!deprecated, "CONTRACT_DEPRECATED");
        require(!isPaused, "NEW_TOKEN_CREATION_IS_PAUSED");

        bytes32 create2Salt = keccak256(abi.encode(creator_, salt_));
        token = new DelaunchTokenV2{salt: create2Salt}(
            name_,
            symbol_,
            _tokenBaseSupply,
            address(this),
            creator_,
            address(0)
        );

        // Ensure token address is less than WAVAX for consistency
        if (address(token) >= _wavax) revert("INVALID SALT");

        address t = address(token);
        allTokens.push(t);

        _tokens[t].creator = creator_;
        _tokens[t].avaxReserve = 0;
        _tokens[t].hasLaunched = false;
        _tokens[t].pairAddress = address(0);
        _tokens[t].lockerAddress = address(0);
        _tokens[t].newTokenAddress = address(0);

        IERC20(t).approve(address(_positionManager), type(uint256).max);
        emit TokenCreated(msg.sender, t, creator_, metadataUri);

        // scope to avoid stack too deep
        {
            if (msg.value > 0) {
                Token storage tt = _tokens[t];
                require(!tt.hasLaunched, "ALREADY_LAUNCHED");

                uint256 fee = (msg.value * _curveConfig.curveFee) / 10000;
                uint256 value = msg.value - fee;
                uint256 refund = 0;
                bool _curveCompleted = false;

                uint256 requiredAvaxToCompleteCurve = _clPoolConfig
                    .targetPoolAvaxBalance - tt.avaxReserve;

                if (value >= requiredAvaxToCompleteCurve) {
                    _curveCompleted = true;
                    value = requiredAvaxToCompleteCurve;
                    fee = (value * _curveConfig.curveFee) / 10000;
                    refund = msg.value - value - fee;
                }

                uint256 amountOut = getBuyAmountOut(t, value);
                tt.avaxReserve += value;

                require(
                    IERC20(t).transfer(msg.sender, amountOut),
                    "ERC20 transfer to buyer failed"
                );

                (bool success, ) = feeReceiver.call{value: fee}("");
                require(success, "Failed to send Ether to feeReceiver");

                emit Swap(t, msg.sender, 0, amountOut, msg.value, 0);

                if (_curveCompleted) {
                    (bool sent, ) = msg.sender.call{value: refund}("");
                    require(sent, "Failed to refund Ether");

                    _launchToken(t);
                }
            }
        }
    }

    //returns the supply of the token outside the bonding curve
    function getCirculatingSupply(
        address token0
    ) public view returns (uint256) {
        uint256 totalSupply = IERC20(token0).totalSupply();
        uint256 balanceOfBondingCurve = IERC20(token0).balanceOf(address(this));
        return totalSupply - balanceOfBondingCurve;
    }

    function getBuyAmountOut(
        address token0,
        uint256 amountIn
    ) public view returns (uint256) {
        Token memory t = _tokens[token0];
        require(!t.hasLaunched, "ALREADY_LAUNCHED");
        require(amountIn > 0, "INVALID_AMOUNT");

        uint256 circulatingSupply = getCirculatingSupply(token0);
        return
            calculatePurchaseReturn(circulatingSupply, t.avaxReserve, amountIn);
    }

    function getSellAmountOut(
        address token0,
        uint256 amountIn
    ) public view returns (uint256) {
        Token memory t = _tokens[token0];
        require(!t.hasLaunched, "ALREADY_LAUNCHED");
        require(amountIn > 0, "INVALID_AMOUNT");

        uint256 circulatingSupply = getCirculatingSupply(token0);

        return calculateSaleReturn(circulatingSupply, t.avaxReserve, amountIn);
    }

    function buy(
        address token0,
        uint256 amountOutMin
    )
        external
        payable
        nonReentrant
        returns (
            uint256 value,
            uint256 amountOut,
            address pairAddress,
            uint256 tokenId,
            address lockerAddress
        )
    {
        Token storage t = _tokens[token0];
        require(!t.hasLaunched, "ALREADY_LAUNCHED");
        require(msg.value >= 0.01 ether, "NOT_ENOUGH_AVAX");

        uint256 fee = (msg.value * _curveConfig.curveFee) / 10000;
        value = msg.value - fee;
        uint256 refund = 0;

        bool _curveCompleted = false;

        uint256 requiredAvaxToCompleteCurve = _clPoolConfig
            .targetPoolAvaxBalance - t.avaxReserve;

        if (value >= requiredAvaxToCompleteCurve) {
            _curveCompleted = true;
            value = requiredAvaxToCompleteCurve;
            fee = (value * _curveConfig.curveFee) / 10000;
            refund = msg.value - value - fee;
        }

        amountOut = getBuyAmountOut(token0, value);
        require(amountOut >= amountOutMin, "EXCEEDED SLIPPAGE LIMIT");

        t.avaxReserve += value;

        require(
            IERC20(token0).transfer(msg.sender, amountOut),
            "ERC20 transfer to buyer failed"
        );

        (bool success, ) = feeReceiver.call{value: fee}("");
        require(success, "Failed to send Ether to feeReceiver");

        emit Swap(token0, msg.sender, 0, amountOut, msg.value, 0);

        if (_curveCompleted) {
            (bool sent, ) = msg.sender.call{value: refund}("");
            require(sent, "Failed to refund Ether");

            (tokenId, pairAddress, lockerAddress) = _launchToken(token0);
        }
    }

    function sell(
        address token0,
        uint256 amountIn,
        uint256 amountOutMin
    ) external nonReentrant returns (uint256 finalAmountOut) {
        Token storage t = _tokens[token0];
        require(!t.hasLaunched, "ALREADY_LAUNCHED");
        require(amountIn > 0, "INVALID_AMOUNT");

        uint256 amountOut = getSellAmountOut(token0, amountIn);
        require(amountOut >= amountOutMin, "EXCEEDED SLIPPAGE LIMIT");

        require(
            IERC20(token0).transferFrom(msg.sender, address(this), amountIn),
            "TRANSFER_FAILED"
        );

        require(
            amountOut <= t.avaxReserve,
            "Curve does not have sufficient funds"
        );

        uint256 _fee = (amountOut * _curveConfig.curveFee) / 10000;
        (bool success, ) = feeReceiver.call{value: _fee}("");
        require(success, "Failed to send Ether to feeReceiver");

        finalAmountOut = amountOut - _fee;

        (bool sent, ) = msg.sender.call{value: finalAmountOut}("");
        require(sent, "Failed to send Ether to seller");

        t.avaxReserve -= amountOut;

        emit Swap(token0, msg.sender, amountIn, 0, 0, amountOut);
    }

    function _launchToken(
        address token0
    )
        internal
        returns (uint256 tokenId, address pairAddress, address lockerAddress)
    {
        Token storage originalToken = _tokens[token0];
        require(!originalToken.hasLaunched, "ALREADY_LAUNCHED");

        uint256 _wavaxIntoPool = _clPoolConfig.targetPoolAvaxBalance -
            _curveConfig.launchFee;

        (bool success, ) = feeReceiver.call{value: _curveConfig.launchFee}("");
        require(success, "Failed to send Ether");

        address targetTokenAddress = token0;
        address newTokenAddress = address(0);

        pairAddress = _pharaohFactory.getPool(
            targetTokenAddress,
            _wavax,
            _clPoolConfig.poolFee
        );
        if (pairAddress != address(0)) {
            IDelaunchTokenV2 _token = IDelaunchTokenV2(token0);
            (bytes32 _salt, ) = generateSalt(
                _token.name(),
                _token.symbol(),
                _token.creator()
            );

            bytes32 _create2Salt = keccak256(
                abi.encode(_token.creator(), _salt)
            );
            DelaunchTokenV2 token = new DelaunchTokenV2{salt: _create2Salt}(
                _token.name(),
                _token.symbol(),
                _tokenBaseSupply,
                address(this),
                _token.creator(),
                token0
            );

            // Ensure token address is less than WAVAX for consistency
            if (address(token) >= _wavax) revert("INVALID SALT");

            address t = address(token);

            originalToken.newTokenAddress = t;
            targetTokenAddress = t;
        }

        IDelaunchTokenV2(targetTokenAddress).completeTheCurve();

        pairAddress = _positionManager.createAndInitializePoolIfNecessary(
            targetTokenAddress,
            _wavax,
            _clPoolConfig.poolFee,
            _clPoolConfig.sqrtPriceX96
        );

        IWNATIVE(_wavax).deposit{value: _wavaxIntoPool}();
        IWNATIVE(_wavax).approve(address(_positionManager), type(uint256).max);

        uint256 _contractTokenBalance = IERC20(targetTokenAddress).balanceOf(
            address(this)
        );

        uint256 _tokenSupply = (_tokenBaseSupply *
            (10000 - _curveConfig.poolShare)) / 10000;

        uint256 _tokenSupplyFinal;

        //fallback if the contract balance is less than the target supply for any reason
        if (_contractTokenBalance < _tokenSupply) {
            _tokenSupplyFinal = _contractTokenBalance;
        } else {
            _tokenSupplyFinal = _tokenSupply;
        }

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: _wavax,
                fee: _clPoolConfig.poolFee,
                tickLower: _clPoolConfig.tickLower,
                tickUpper: _clPoolConfig.tickUpper,
                amount0Desired: _tokenSupplyFinal,
                amount1Desired: _wavaxIntoPool,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp,
                veNFTTokenId: 0
            });

        (tokenId, , , ) = _positionManager.mint(params);

        lockerAddress = _liquidityLockerFactory.deploy(
            address(_positionManager),
            originalToken.creator,
            _clPoolConfig.lpLockPeriod,
            tokenId,
            _clPoolConfig.creatorFeeCut,
            100 - _clPoolConfig.creatorFeeCut,
            address(this)
        );

        _positionManager.safeTransferFrom(
            address(this),
            lockerAddress,
            tokenId
        );
        ILocker(lockerAddress).initializer(tokenId);

        originalToken.hasLaunched = true;
        originalToken.pairAddress = pairAddress;
        originalToken.lockerAddress = lockerAddress;

        emit CurveCompleted(
            token0,
            newTokenAddress,
            pairAddress,
            lockerAddress
        );
    }

    function claimNewTokens(
        address originalToken,
        uint256 amountIn
    ) external nonReentrant {
        Token storage t = _tokens[originalToken];
        require(t.hasLaunched, "NOT_LAUNCHED");
        require(t.newTokenAddress != address(0), "NO_NEW_TOKEN");

        IERC20(originalToken).transferFrom(msg.sender, address(this), amountIn);
        IERC20(t.newTokenAddress).transfer(msg.sender, amountIn);

        emit TokenClaimed(
            originalToken,
            t.newTokenAddress,
            msg.sender,
            amountIn
        );
    }

    function predictToken(
        string memory name,
        string memory symbol,
        address creator,
        bytes32 salt
    ) public view returns (address) {
        bytes32 create2Salt = keccak256(abi.encode(creator, salt));
        return
            keccak256(
                abi.encodePacked(
                    bytes1(0xFF),
                    address(this),
                    create2Salt,
                    keccak256(
                        abi.encodePacked(
                            type(DelaunchTokenV2).creationCode,
                            abi.encode(
                                name,
                                symbol,
                                _tokenBaseSupply,
                                address(this),
                                creator
                            )
                        )
                    )
                )
            ).fromLast20Bytes();
    }

    function generateSalt(
        string memory name,
        string memory symbol,
        address creator
    ) public view returns (bytes32 salt, address token) {
        for (uint256 i; ; i++) {
            salt = bytes32(i);
            token = predictToken(name, symbol, creator, salt);
            if (token < _wavax && token.code.length == 0) {
                break;
            }
        }
    }

    function allTokensLength() external view returns (uint256) {
        return allTokens.length;
    }

    function getFeeReceiver() external view returns (address) {
        return feeReceiver;
    }

    function clPoolConfig() public view returns (ClPoolConfig memory) {
        return _clPoolConfig;
    }

    function curveConfig() public view returns (CurveConfig memory) {
        return _curveConfig;
    }

    function tokens(address token) public view returns (Token memory) {
        return _tokens[token];
    }

    // Owner
    function changeFeeReceiver(address feeReceiver_) external onlyOwner {
        feeReceiver = feeReceiver_;
    }

    function changeCurveTradingFee(uint24 newFee_) external onlyOwner {
        require(newFee_ <= 250, "FEE_TOO_HIGH");
        _curveConfig.curveFee = newFee_;
    }

    function changeCurveLaunchFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= 25 ether, "FEE_TOO_HIGH");
        _curveConfig.launchFee = newFee_;
    }

    function setIsPaused(bool isPaused_) external onlyOwner {
        isPaused = isPaused_;
    }

    function setDeprecated(bool deprecated_) external onlyOwner {
        deprecated = deprecated_;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
