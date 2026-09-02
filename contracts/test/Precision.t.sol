// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract PrecisionTest is BaseSetup {
    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }

    function test_MinSupplyWithdrawNoLoss() public {
        _supply(alice, 10e6); // 最小存款 10 USDC
        assertEq(pool.totalShares(), 10e6);
        vm.prank(alice);
        pool.withdraw(0, 10e6);
        assertEq(pool.totalShares(), 0);
        assertEq(pool.cash(), 0);
        assertEq(usdc.balanceOf(alice), 500_000e6);
        _assertInvariant();
    }

    function test_MinBorrowRepayNoLoss() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 100e6, 1); // 最小借款 100 USDC
        uint256 debt = pool.getDebt(alice);
        assertGt(debt, 0);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(0, type(uint256).max);
        assertEq(pool.getDebt(alice), 0);
        assertEq(pool.getTotalBorrows(), 0);
        _assertInvariant();
    }

    function test_MinSupplyEarnsInterest() public {
        _supply(bob, 10_000e6); // 大流动性池
        _supply(alice, 10e6); // 最小份额存款
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 1000e6, 5);
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        // 极小份额也不亏损
        (uint256 shares,,,,,,) = pool.getUserPosition(alice);
        assertEq(shares, 10e6);
        uint256 claimable = shares * pool.supplyIndex() / 1e18;
        assertGe(claimable, 10e6);
        vm.prank(alice);
        pool.withdraw(0, shares);
        assertGe(usdc.balanceOf(alice), 500_000e6);
        _assertInvariant();
    }

    function test_BorrowRoundingIsUpwardSafe() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 999e6, 5);
        // 债务永远 >= 借入额（向上取整，利于协议而非借款人）
        assertGe(pool.getDebt(alice), 999e6 * 1e12);
    }

    function test_WithdrawRoundingNeverExceedsShare() public {
        _supply(alice, 123_457e6); // 非整数关系
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 2000e6, 5);
        vm.warp(block.timestamp + 100 days);
        pool.accrue();
        uint256 claimable = pool.getTotalSupply();
        // 任意次部分取款后，累计取款 <= 理论可提取
        uint256 totalWithdrawn;
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(alice);
            pool.withdraw(0, 20_000e6);
            totalWithdrawn += 20_000e6 * pool.supplyIndex() / 1e18;
        }
        assertLe(totalWithdrawn, claimable);
        _assertInvariant();
    }

    function test_MinimumUnitLiquidationNoLoss() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5); // LTV 66.7%
        oracle.setPrice(ETH, 2000e8); // HF = 0.9
        _approveUsdc(liquidator, type(uint256).max);
        uint256 debtBefore = pool.getDebt(alice);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1, 0); // 只清算 1 微 USDC
        // 债务精确减少 1 微（1e12 WAD）
        assertApproxEqAbs(pool.getDebt(alice), debtBefore - 1e12, 1e12);
        _assertInvariant();
        assertApproxEqAbs(pool.getTotalBorrows() * 1e12, pool.getDebt(alice), 1e12);
    }
}
