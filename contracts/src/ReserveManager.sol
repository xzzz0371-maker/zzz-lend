// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IReserveManager {
    /// @notice Transfers `amount` USDC to the configured lending pool (bad debt coverage).
    function coverBadDebt(uint256 amount) external;
}

contract ReserveManager is Ownable, IReserveManager {
    IERC20 public immutable usdc;
    address public lendingPool;

    event LendingPoolSet(address pool);
    event BadDebtCovered(uint256 amount);

    constructor(address usdc_) Ownable(msg.sender) {
        usdc = IERC20(usdc_);
    }

    function setLendingPool(address pool) external onlyOwner {
        require(pool != address(0), "zero address");
        lendingPool = pool;
        emit LendingPoolSet(pool);
    }

    /// @notice Only the configured lending pool may trigger coverage; funds can only go back to that pool.
    function coverBadDebt(uint256 amount) external {
        require(msg.sender == lendingPool, "not pool");
        require(amount > 0, "amount=0");
        emit BadDebtCovered(amount);
        require(usdc.transfer(lendingPool, amount), "transfer failed");
    }

    function balance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }
}
