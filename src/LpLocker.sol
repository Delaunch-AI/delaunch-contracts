// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./libraries/PoolAddress.sol";
import {NonFungibleContract} from "./interfaces/IManager.sol";
import "./interfaces/IDelaunchFactoryV2.sol";

contract LpLocker is IERC721Receiver {
    event ERC721Released(address indexed token, uint256 amount);
    event LockId(uint256 _id);
    event LockDuration(uint256 _time);
    event Received(address indexed from, uint256 tokenId);
    event ClaimedFees(
        address indexed claimer,
        address indexed token0,
        address indexed token1,
        uint256 amount0,
        uint256 amount1,
        uint256 totalAmount0,
        uint256 totalAmount1
    );

    uint256 private _released;
    mapping(address => uint256) public _erc721Released;
    IERC721 private SafeERC721;
    uint64 private immutable _duration; // This is now the end timestamp
    address private immutable e721Token;
    bool private flag;
    NonFungibleContract private positionManager;
    IDelaunchFactoryV2 public delaunchFactory;
    uint256 public creatorFeeCut;
    uint256 public protocolFeeCut;
    address public immutable creator;
    uint256 public immutable tokenId;

    constructor(
        uint256 _tokenId,
        address token,
        address _creator,
        uint64 durationSeconds,
        uint256 _creatorFeeCut,
        uint256 _protocolFeeCut,
        address _delaunchFactory
    ) payable {
        require(_creatorFeeCut <= 100, "Invalid creator fee cut");
        _duration = uint64(block.timestamp) + durationSeconds; // Store end timestamp
        SafeERC721 = IERC721(token);
        flag = false;
        e721Token = token;
        creatorFeeCut = _creatorFeeCut;
        protocolFeeCut = _protocolFeeCut;
        delaunchFactory = IDelaunchFactoryV2(_delaunchFactory);

        creator = _creator;
        tokenId = _tokenId;

        emit LockDuration(_duration);
    }

    modifier onlyFeeReceiver() {
        address feeReceiver = delaunchFactory.getFeeReceiver();
        require(feeReceiver == msg.sender, "only feeReceiver can call");
        _;
    }

    function initializer(uint256 token_id) public {
        require(flag == false, "contract already initialized");
        _erc721Released[e721Token] = token_id;
        flag = true;
        positionManager = NonFungibleContract(e721Token);

        if (positionManager.ownerOf(token_id) != address(this)) {
            SafeERC721.transferFrom(creator, address(this), token_id);
        }

        emit LockId(token_id);
    }

    function duration() public view virtual returns (uint256) {
        return _duration;
    }

    receive() external payable virtual {}

    function end() public view virtual returns (uint256) {
        return duration();
    }

    function released(address token) public view virtual returns (uint256) {
        return _erc721Released[token];
    }

    function release() public virtual onlyFeeReceiver {
        if (vestingSchedule() != 0) {
            revert();
        }

        uint256 id = _erc721Released[e721Token];
        emit ERC721Released(e721Token, id);
        SafeERC721.transferFrom(address(this), msg.sender, id);
    }

    function withdrawERC20(address _token) public onlyFeeReceiver {
        IERC20 IToken = IERC20(_token);
        IToken.transferFrom(
            address(this),
            msg.sender,
            IToken.balanceOf(address(this))
        );
    }

    function collectFees(address _recipient) public returns (uint256, uint256) {
        address feeReceiver = delaunchFactory.getFeeReceiver();

        require(
            msg.sender == creator || msg.sender == feeReceiver,
            "only creator or feeReceiver can call"
        );

        if (_recipient == address(0)) {
            _recipient = creator;
        }

        (uint256 amount0, uint256 amount1) = positionManager.collect(
            NonFungibleContract.CollectParams({
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max,
                tokenId: tokenId
            })
        );

        // Get token addresses
        (, , address token0, address token1, , , , , , , , ) = positionManager
            .positions(tokenId);

        IERC20 feeToken0 = IERC20(token0);
        IERC20 feeToken1 = IERC20(token1);

        // Calculate fee splits
        uint256 protocolFee0 = (amount0 * protocolFeeCut) / 100;
        uint256 protocolFee1 = (amount1 * protocolFeeCut) / 100;

        uint256 creatorFee0 = (amount0 * creatorFeeCut) / 100;
        uint256 creatorFee1 = (amount1 * creatorFeeCut) / 100;

        uint256 remainingFee0 = amount0 - protocolFee0 - creatorFee0;
        uint256 remainingFee1 = amount1 - protocolFee1 - creatorFee1;

        // Transfer protocol fees
        if (protocolFee0 > 0) feeToken0.transfer(feeReceiver, protocolFee0);
        if (protocolFee1 > 0) feeToken1.transfer(feeReceiver, protocolFee1);

        // Transfer creator fees
        if (creatorFee0 > 0) feeToken0.transfer(_recipient, creatorFee0);
        if (creatorFee1 > 0) feeToken1.transfer(_recipient, creatorFee1);

        // Transfer remaining fees
        if (remainingFee0 > 0) feeToken0.transfer(_recipient, remainingFee0);
        if (remainingFee1 > 0) feeToken1.transfer(_recipient, remainingFee1);

        emit ClaimedFees(
            _recipient,
            token0,
            token1,
            amount0 - protocolFee0,
            amount1 - protocolFee1,
            amount0,
            amount1
        );

        return (creatorFee0, creatorFee1);
    }

    function vestingSchedule() public view returns (uint256) {
        if (block.timestamp >= duration()) {
            return 0;
        } else {
            return duration() - block.timestamp;
        }
    }

    function onERC721Received(
        address,
        address from,
        uint256 id,
        bytes calldata
    ) external override returns (bytes4) {
        emit Received(from, id);
        return IERC721Receiver.onERC721Received.selector;
    }
}
