// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

// 0xAAAE99091Fbb28D400029052821653C1C752483B -- swapRouter proxy
// 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7 -- WETH9

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);
}

interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ISwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /// @notice Swaps `amountIn` of one token for as much as possible of another token
    /// @param params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata
    /// @return amountOut The amount of the received token
    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

contract CLBuyContract {
    ISwapRouter public immutable swapRouter;
    address public immutable owner;
    address public immutable WETH9;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address swapRouter_, address _WETH9) {
        swapRouter = ISwapRouter(swapRouter_);
        WETH9 = _WETH9; // wavax
        owner = msg.sender; // the owner is the one that creates the contract
        IERC20(WETH9).approve(swapRouter_, type(uint256).max);
    }

    receive() external payable {}

    function buySingle(
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        uint24 fee
    ) public payable returns (uint256) {
        require(
            amountIn <= IWETH9(WETH9).balanceOf(address(this)),
            "Insufficient WAVAX in contract"
        );

        if (
            IERC20(WETH9).allowance(address(this), address(swapRouter)) <
            amountIn
        ) {
            IERC20(WETH9).approve(address(swapRouter), type(uint256).max);
        }

        ISwapRouter.ExactInputSingleParams memory inputParams = ISwapRouter
            .ExactInputSingleParams(
                WETH9, // tokenIn
                tokenOut, // tokenOut
                fee, // fee
                msg.sender, // recipient: the caller
                block.timestamp + 300, // deadline: in 5mins
                amountIn, // amountIn
                amountOutMin, // amountOutMin
                0 // sqrtPriceLimitX96;
            );

        uint256 amountOut = swapRouter.exactInputSingle(inputParams);
        return amountOut;
    }

    function depositWavax() public payable {
        IWETH9(WETH9).deposit{value: msg.value}();
    }

    function wrapNative() public payable {
        IWETH9(WETH9).deposit{value: msg.value}();
    }

    // withdraw specific amount of tokens from contract
    function withdrawToken(address token, uint256 amount) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        require(
            amount <= tokenContract.balanceOf(address(this)),
            "Insufficient token balance"
        );
        require(tokenContract.transfer(msg.sender, amount), "Transfer failed");
    }

    // withdraw all Tokens from contract
    function withdrawAllToken(address token) external onlyOwner {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(tokenContract.transfer(msg.sender, balance), "Transfer failed");
    }

    function checkAllowance(address token) external view returns (uint256) {
        IERC20 tokenContract = IERC20(token);
        uint256 amountAllowed = tokenContract.allowance(
            msg.sender,
            address(swapRouter)
        ); // owner , spender
        return amountAllowed;
    }

    // Helper function to withdraw native token
    function withdrawNative(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient AVAX balance");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Native token transfer failed");
    }

    // Helper function to withdraw all native token
    function withdrawAllNative() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = msg.sender.call{value: balance}("");
        require(success, "Native token transfer failed");
    }
}
