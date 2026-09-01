// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract RepayTest is BaseSetup {
    function test_PartialRepayReducesDebt() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether); // 6000 USD
        _borrow(alice, 4000e6, 5);
        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        uint256 debtBefore = pool.getDebt(alice);

        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(2000e6);

        uint256 debtAfter = pool.getDebt(alice);
        assertApproxEqAbs(debtAfter, debtBefore - 2000e6 * 1e12, 1e12);
        _assertInvariant();
    }

    function test_MultipleSmallRepaysAndFullClear() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether);
        _borrow(alice, 4000e6, 5);
        _approveUsdc(alice, type(uint256).max);

        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 3 days);
            vm.prank(alice);
            pool.repay(100e6);
        }
        assertGt(pool.getDebt(alice), 0);

        vm.prank(alice);
        pool.repay(type(uint256).max);
        assertEq(pool.getDebt(alice), 0);
        assertEq(pool.getTotalBorrows(), 0);
        _assertInvariant();
    }

    function test_PartialRepayKeepsTierLocked() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether);
        _borrow(alice, 2000e6, 1); // 50% LTV
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(1000e6);
        // 部分还款后仍锁定原档位
        vm.expectRevert(bytes("tier locked"));
        _borrow(alice, 1000e6, 5);
    }

    function test_RepayMoreThanDebtCapsToDebt() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 5);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(1_000_000e6); // 远超债务
        // 只按债务扣减
        assertEq(pool.getDebt(alice), 0);
        _assertInvariant();
    }

    function test_RepayInterestCompoundingCorrect() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether);
        _borrow(alice, 3000e6, 5); // 50% LTV
        _approveUsdc(alice, type(uint256).max);

        vm.warp(block.timestamp + 180 days);
        pool.accrue();
        uint256 debtBefore = pool.getDebt(alice);

        vm.prank(alice);
        pool.repay(1000e6);
        uint256 debtMid = pool.getDebt(alice);

        // 再累计 180 天，剩余债务继续计息
        vm.warp(block.timestamp + 180 days);
        pool.accrue();
        uint256 debtAfter = pool.getDebt(alice);
        assertGt(debtAfter, debtMid);
        assertLt(debtAfter, debtBefore); // 因为已经还了 1000
        _assertInvariant();
    }

    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued() + pool.boostPool();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }
}
