// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LpLocker} from "./LpLocker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract LockerFactory is Ownable {
    event Deployed(
        address indexed lockerAddress,
        address indexed owner,
        uint256 tokenId,
        uint256 lockingPeriod,
        uint256 creatorFeeCut,
        uint256 protocolFeeCut
    );

    constructor() Ownable(msg.sender) {}

    function deploy(
        address token,
        address beneficiary,
        uint64 durationSeconds,
        uint256 tokenId,
        uint256 creatorFeeCut,
        uint256 protocolFeeCut,
        address delaunchFactory
    ) public payable returns (address) {
        address newLockerAddress = address(
            new LpLocker(
                tokenId,
                token,
                beneficiary,
                durationSeconds,
                creatorFeeCut,
                protocolFeeCut,
                delaunchFactory
            )
        );

        if (newLockerAddress == address(0)) {
            revert("Invalid address");
        }

        emit Deployed(
            newLockerAddress,
            beneficiary,
            tokenId,
            durationSeconds,
            creatorFeeCut,
            protocolFeeCut
        );

        return newLockerAddress;
    }
}
