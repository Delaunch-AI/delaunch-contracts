// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IDelaunchTokenV2 is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function factory() external view returns (address);
    function deployer() external view returns (address);
    function creator() external view returns (address);
    function curveComplete() external view returns (bool);
    function completeTheCurve() external;
    function originalToken() external view returns (address);
}
