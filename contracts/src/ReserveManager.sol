// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IReserveManager {
    /// @notice Transfers `amount` of `token` to the configured lending pool (bad debt coverage).
    function coverBadDebt(address token, uint256 amount) external;
}

/// @notice 储备管理器（V2 多市场版）。储备按 token 分别存放/覆盖；首个 token（构造传入）为默认 token，
///         提供 balance()/coverBadDebt(uint256) 便捷接口（兼容 V1 调用）。
contract ReserveManager is Ownable, IReserveManager {
    using SafeERC20 for IERC20;
    IERC20 public immutable defaultToken;
    address public lendingPool;

    event LendingPoolSet(address pool);
    event BadDebtCovered(address indexed token, uint256 amount);

    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "zero token");
        defaultToken = IERC20(token_);
    }

    function setLendingPool(address pool) external onlyOwner {
        require(pool != address(0), "zero address");
        lendingPool = pool;
        emit LendingPoolSet(pool);
    }

    /// @notice Only the configured lending pool may trigger coverage; funds can only go back to that pool.
    function coverBadDebt(address token, uint256 amount) external {
        _coverBadDebt(token, amount);
    }

    /// @notice 默认 token 便捷覆盖（兼容 V1）。
    function coverBadDebt(uint256 amount) external {
        _coverBadDebt(address(defaultToken), amount);
    }

    function _coverBadDebt(address token, uint256 amount) internal {
        require(msg.sender == lendingPool, "not pool");
        require(amount > 0, "amount=0");
        require(token != address(0), "zero token");
        emit BadDebtCovered(token, amount);
        IERC20(token).safeTransfer(lendingPool, amount);
    }

    function balanceOf(address token) external view returns (uint256) {
        return token == address(0) ? 0 : IERC20(token).balanceOf(address(this));
    }

    /// @notice 默认 token 余额（兼容 V1）。
    function balance() external view returns (uint256) {
        return IERC20(address(defaultToken)).balanceOf(address(this));
    }
}
