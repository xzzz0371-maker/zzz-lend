// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    uint8 public constant DECIMALS = 6;

    constructor() ERC20("Mock USDC", "USDC") {}

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}
