// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract LiquidationTest is BaseSetup {
    function test_HealthyPositionNotLiquidatable() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrow(alice, 1000e6, 5); // LTV 33%
        vm.prank(liquidator);
        vm.expectRevert(bytes("not liquidatable"));
        pool.liquidate(alice, 100e6, 0);
    }

    function test_LiquidationAfterPriceDrop() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrow(alice, 2000e6, 5); // LTV 66.7%
        oracle.setPrice(ETH, 2000e8); // collateral 2000, HF = 2000*0.9/2000 = 0.9 < 1
        uint256 debtBefore = pool.getDebt(alice);
        (, uint256 collateralBefore,,,,,) = pool.getUserPosition(alice);

        uint256 liquidatorEthBefore = liquidator.balance;
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 1000e6, 0); // cover 1000, seize = 1000*1.05/2000 = 0.525 ETH

        uint256 debtAfter = pool.getDebt(alice);
        assertLt(debtAfter, debtBefore);
        // debt reduced by 1000 USDC
        assertApproxEqAbs(debtAfter, debtBefore - 1000e6 * 1e12, 1e6 * 1e12);
        // collateral reduced by ~0.525 ETH
        (, uint256 collateralAfter,,,,,) = pool.getUserPosition(alice);
        uint256 seized = collateralBefore - collateralAfter;
        assertApproxEqAbs(seized, 0.525 ether, 1e15);
        // liquidator received ETH
        assertEq(liquidator.balance - liquidatorEthBefore, seized);
        // liquidator paid USDC
        assertLt(usdc.balanceOf(liquidator), 500_000e6);
    }

    function test_CloseFactorCapsCoverage() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8);
        uint256 debtBefore = pool.getDebt(alice);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 10_000e6, 0); // ask huge; capped to 50%
        uint256 covered = (debtBefore - pool.getDebt(alice)) / 1e12;
        assertApproxEqAbs(covered, debtBefore / 1e12 / 2, 1e6);
    }

    function test_SelfLiquidationReverts() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8);
        vm.prank(alice);
        vm.expectRevert(bytes("self-liquidation"));
        pool.liquidate(alice, 100e6, 0);
    }

    function test_BadDebtCoveredByReserve() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrow(alice, 2400e6, 5); // 80% LTV
        // accrue interest for a year so the risk reserve accumulates
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        assertGt(pool.totalReserve(), 0);
        // move reserve USDC out of the pool into the ReserveManager
        pool.skimReserve();
        assertGt(reserveManager.balance(), 0);

        // crash price: collateral ~= 0
        oracle.setPrice(ETH, 1e8);

        uint256 poolCashBefore = pool.cash();
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 10_000e6, 0); // drains all collateral, debt remains

        // alice has zero collateral and leftover debt -> bad debt
        (, uint256 collateralAfterLiquidation,,,,,) = pool.getUserPosition(alice);
        assertEq(collateralAfterLiquidation, 0);
        uint256 debtBeforeWriteOff = pool.getDebt(alice) / 1e12;
        assertGt(debtBeforeWriteOff, 0);

        // 资金守恒：清算后（坏账传导前）
        assertApproxEqAbs(
            pool.cash() + pool.getTotalBorrows(),
            pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued() + pool.boostPool(),
            1e7
        );

        uint256 reserveBalanceBefore = reserveManager.balance();
        uint256 supplyIndexBefore = pool.supplyIndex();
        uint256 supplyBefore = pool.getTotalSupply();
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice);

        // 储备覆盖 min(储备, 债务)；alice 债务 > 储备 → 储备耗尽
        uint256 covered6 = reserveBalanceBefore - reserveManager.balance();
        assertGt(covered6, 0);
        assertEq(reserveManager.balance(), 0);
        assertEq(pool.getDebt(alice), 0); // 仓位清零
        // 未覆盖部分即时传导给存款人：supplyIndex 下降
        uint256 loss6 = debtBeforeWriteOff - covered6;
        assertGt(loss6, 0);
        assertLt(pool.supplyIndex(), supplyIndexBefore);
        assertApproxEqAbs(pool.getTotalSupply(), supplyBefore - loss6, 1e7);
        // reserve 转回池
        assertLt(reserveManager.balance(), reserveBalanceBefore);
        assertGt(pool.cash(), poolCashBefore);
        // 资金守恒：坏账传导后仍守恒
        assertApproxEqAbs(
            pool.cash() + pool.getTotalBorrows(),
            pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued() + pool.boostPool(),
            1e7
        );
    }

    function test_BadDebtRequiresZeroCollateral() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8); // still has collateral
        vm.prank(liquidator);
        vm.expectRevert(bytes("collateral exists"));
        pool.handleBadDebt(alice);
    }

    function test_LiquidationCannotHappenTwiceOnHealthyPosition() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 5);
        oracle.setPrice(ETH, 1500e8); // HF = 1500*0.9/1000 = 1.35 healthy
        vm.prank(liquidator);
        vm.expectRevert(bytes("not liquidatable"));
        pool.liquidate(alice, 100e6, 0);
    }
}
