// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILockerFactory {
    function deploy(
        address token,
        address beneficiary,
        uint64 durationSeconds,
        uint256 tokenId,
        uint256 fees
    ) external payable returns (address);
}
