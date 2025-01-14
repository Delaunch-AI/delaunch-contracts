// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILpLocker {
    // Events
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

    // View functions
    function duration() external view returns (uint256);
    function end() external view returns (uint256);
    function released(address token) external view returns (uint256);
    function vestingSchedule() external view returns (uint256);
    function delaunchFactory() external view returns (address);
    function creatorFeeCut() external view returns (uint256);
    function protocolFeeCut() external view returns (uint256);
    function creator() external view returns (address);
    function tokenId() external view returns (uint256);
    function _erc721Released(address) external view returns (uint256);

    // State-changing functions
    function initializer(uint256 token_id) external;
    function release() external;
    function withdrawERC20(address _token) external;
    function collectFees(
        address _recipient
    ) external returns (uint256, uint256);

    // IERC721Receiver function
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);

    // Fallback function
    receive() external payable;
}
