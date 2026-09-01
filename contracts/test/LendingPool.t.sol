// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract LendingPoolTest is BaseSetup {
    function test_SupplyMintsShares() public {
        _supply(alice, 1000e6);
        assertEq(pool.totalShares(), 1000e6);
        assertEq(pool.getTotalSupply(), 1000e6);
        assertEq(pool.cash(), 1000e6);
        (uint256 shares,,,,,,) = pool.getUserPosition(alice);
        assertEq(shares, 1000e6);
        assertEq(usdc.balanceOf(alice), 499_000e6);
    }

    function test_WithdrawRoundTrip() public {
        _supply(alice, 1000e6);
        vm.prank(alice);
        pool.withdraw(1000e6);
        assertEq(usdc.balanceOf(alice), 500_000e6);
        assertEq(pool.totalShares(), 0);
        assertEq(pool.cash(), 0);
    }

    function test_WithdrawMoreThanOwnedReverts() public {
        _supply(alice, 1000e6);
        vm.prank(alice);
        vm.expectRevert(bytes("insufficient shares"));
        pool.withdraw(1001e6);
    }

    function test_BorrowRequiresCollateral() public {
        _supply(bob, 10_000e6);
        vm.prank(bob);
        vm.expectRevert(bytes("no collateral"));
        pool.borrow(100e6, 1);
    }

    function test_BorrowRespectsTierLtv() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        _borrow(alice, 1500e6, 1); // 50% LTV = exactly 1500
        vm.expectRevert(bytes("ltv too high"));
        _borrow(alice, 100e6, 1); // 1600 > 1500
    }

    function test_HigherTierAllowsMoreBorrow() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        _borrow(alice, 2400e6, 5); // 80% LTV
        vm.expectRevert(bytes("ltv too high"));
        _borrow(alice, 100e6, 5);
    }

    function test_TierLockedUntilRepay() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 2 ether); // 6000 USD
        _borrow(alice, 1000e6, 1);
        vm.expectRevert(bytes("tier locked"));
        _borrow(alice, 1000e6, 5);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(type(uint256).max);
        _borrow(alice, 3000e6, 5); // now allowed
        assertEq(pool.getDebt(alice), 3000e6 * 1e12);
    }

    function test_RepayClearsDebt() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 1);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(type(uint256).max);
        assertEq(pool.getDebt(alice), 0);
        (,,,,, uint256 tier,) = pool.getUserPosition(alice);
        assertEq(tier, 0);
        assertEq(pool.getTotalBorrows(), 0);
    }

    function test_InterestAccruesOverTime() public {
        _supply(alice, 10_000e6);
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 2000e6, 5);
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        assertGt(pool.getTotalBorrows(), 2000e6);
        assertGt(pool.getTotalSupply(), 10_000e6);
        assertGt(pool.getSupplyAPR(), 0);
        assertGt(pool.getBorrowAPR(5), 0);
    }

    function test_InterestDistributedProportionally() public {
        _supply(alice, 10_000e6);
        _supply(bob, 20_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        vm.warp(block.timestamp + 180 days);
        pool.accrue();
        (,, uint256 debt,,,,) = pool.getUserPosition(alice);
        assertGt(debt, 0);
        // alice's supply grows proportionally to her share (1/3 of total shares)
        (uint256 aliceShares,,,,,,) = pool.getUserPosition(alice);
        uint256 aliceSupply = pool.getTotalSupply() * aliceShares / pool.totalShares();
        assertApproxEqAbs(aliceSupply, pool.getTotalSupply() / 3, 1e6);
    }

    function test_Utilization() public {
        _supply(alice, 10_000e6);
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 2000e6, 5);
        assertApproxEqAbs(pool.getUtilization(), 2e17, 1e14); // 2000/10000 = 20%
    }

    function test_CannotWithdrawBeyondLiquidity() public {
        _supply(alice, 10_000e6);
        _supplyCollateral(bob, 3 ether); // 9000 USD
        _borrow(bob, 7200e6, 5); // 80% LTV
        // cash now = 10000 - 7200 = 2800
        vm.prank(alice);
        vm.expectRevert(bytes("insufficient liquidity"));
        pool.withdraw(3000e6);
        vm.prank(alice);
        pool.withdraw(2800e6); // exactly cash available
    }

    function test_CannotWithdrawCollateralWhileUnhealthy() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrow(alice, 2400e6, 5); // 80% LTV
        oracle.setPrice(ETH, 2500e8); // collateral 2500, debt 2400
        vm.prank(alice);
        vm.expectRevert(bytes("unhealthy"));
        pool.withdrawCollateral(0.1 ether);
    }

    function test_SupplyAndBorrowFaucetFlow() public {
        _supply(bob, 50_000e6);
        _supplyCollateral(alice, 10 ether);
        _borrow(alice, 20_000e6, 5);
        assertEq(usdc.balanceOf(alice), 500_000e6 + 20_000e6);
        assertEq(pool.cash(), 30_000e6);
    }
}
