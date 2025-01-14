// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../interfaces/IDelaunchTokenV2.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DelaunchTokenV2 is ERC20 {
    address public immutable factory;

    address public immutable deployer;
    address public immutable creator;
    address public immutable originalToken;

    // Bonding Curve Complete
    bool public curveComplete;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 supply_,
        address deployer_,
        address creator_,
        address originalToken_
    ) ERC20(_name, _symbol) {
        factory = msg.sender;
        _mint(msg.sender, supply_);
        deployer = deployer_;
        creator = creator_;
        originalToken = originalToken_;
    }

    function completeTheCurve() external {
        require(msg.sender == factory, "NOT_ALLOWED");
        curveComplete = true;
    }

    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // Is still in bonding curve phase
        super._update(from, to, amount);
        if (!curveComplete) {
            require(
                from == factory || to == factory || from == address(0),
                "Cannot transfer tokens yet"
            );
        }
    }
}
