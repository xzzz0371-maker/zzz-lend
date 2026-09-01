// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {BaseSetup} from "./BaseSetup.t.sol";

/// @notice 固定费率 + 储备溢出自动转 Treasury 测试：
///         固定比例 存款人92% / 储备5% / Treasury3%；储备目标 = totalBorrows × 3%，
///         每次计息后储备超过目标的部分自动转入 Treasury。
contract FeeMechanismTest is BaseSetup {
    event TreasuryCollected(uint256 amount, address to);
    event ReserveOverflowTransferred(uint256 amount);
    event ReserveTargetRatioUpdated(uint256 value);

    function _setupBorrow() internal {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 2 ether);
        _borrow(alice, 3000e6, 5);
    }

    function _setLowTarget() internal {
        vm.prank(admin);
        pool.setReserveTargetRatio(1e15); // 0.1%，便于确定性触发溢出
    }

    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }

    /// @notice 固定费率合计 100%（92 + 5 + 3）。
    function test_FixedFeesSumTo100() public view {
        assertEq(pool.depositorShare(), 94e16);
        assertEq(pool.reserveFactor(), 4e16);
        assertEq(pool.treasuryFactor(), 2e16);
        assertEq(pool.depositorShare() + pool.reserveFactor() + pool.treasuryFactor(), 1e18);
        assertEq(pool.reserveTargetRatio(), 3e16);
    }

    /// @notice 储备未达标：5% 进储备、3% 进 Treasury、92% 给存款人，无溢出。
    function test_ReserveBelowTarget_NoOverflow() public {
        _setupBorrow();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();

        uint256 interest = pool.getTotalBorrows() - 3000e6;
        assertGt(interest, 0);
        assertApproxEqAbs(pool.totalReserve(), interest * 4e16 / 1e18, 1e6);
        assertApproxEqAbs(pool.treasuryAccrued(), interest * 2e16 / 1e18, 1e6);
        assertApproxEqAbs(pool.getTotalSupply() - 200_000e6, interest * 94e16 / 1e18, 1e6);
        uint256 target = pool.getTotalBorrows() * pool.reserveTargetRatio() / 1e18;
        assertLt(pool.totalReserve(), target); // 无溢出
        _assertInvariant();
    }

    /// @notice 储备达标：5% 计息超过目标，超额部分自动转 Treasury，储备收敛到目标。
    function test_ReserveAboveTarget_OverflowToTreasury() public {
        _setupBorrow();
        _setLowTarget();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();

        uint256 interest = pool.getTotalBorrows() - 3000e6;
        assertGt(interest, 0);
        uint256 target = pool.getTotalBorrows() * 1e15 / 1e18;
        assertApproxEqAbs(pool.totalReserve(), target, 1e6); // 溢出后固定在目标
        // treasury = 3% 计息 + 溢出（5% 计息超出目标的部分）
        assertApproxEqAbs(pool.treasuryAccrued(), interest * 6e16 / 1e18 - target, 1e6);
        _assertInvariant();
    }

    /// @notice 储备刚好等于目标时，新增的 5% 全部溢出转 Treasury。
    function test_ReserveAtTarget_NewFivePctFullyOverflows() public {
        _setupBorrow();
        _setLowTarget();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue(); // 建立 target 状态

        uint256 borrowsBefore = pool.getTotalBorrows();
        uint256 supplyBefore = pool.getTotalSupply();
        uint256 treasuryBefore = pool.treasuryAccrued();

        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();

        uint256 interest2 = pool.getTotalBorrows() - borrowsBefore;
        assertGt(interest2, 0);
        assertApproxEqAbs(pool.totalReserve(), pool.getTotalBorrows() * 1e15 / 1e18, 1e6); // 仍=目标
        assertApproxEqAbs(pool.treasuryAccrued() - treasuryBefore, interest2 * 6e16 / 1e18, 1e6); // 2%+4% 全转
        assertApproxEqAbs(pool.getTotalSupply() - supplyBefore, interest2 * 94e16 / 1e18, 1e6);
        _assertInvariant();
    }

    /// @notice 坏账消耗储备后（见改动一）：储备低于目标，溢出停止，重新积累。
    function test_BadDebtConsumesReserve_OverflowStops() public {
        // 两个借款人：alice 将成坏账，bob 保持健康使借款持续
        _supply(bob, 300_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2400e6, 5);
        _supplyCollateral(bob, 2 ether);
        _borrow(bob, 2000e6, 5);
        _setLowTarget();

        // 累计使储备超过目标（溢出中）
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        uint256 targetBefore = pool.getTotalBorrows() * 1e15 / 1e18;
        assertApproxEqAbs(pool.totalReserve(), targetBefore, 1e6);

        // skim 到物理储备，供坏账消耗
        pool.skimReserve();
        assertEq(pool.totalReserve(), 0);
        assertApproxEqAbs(reserveManager.balance(), targetBefore, 1e6);

        // 坏账：alice 抵押归零 → handleBadDebt 耗尽物理储备
        oracle.setPrice(ETH, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 10_000e6, 0);
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice);
        assertEq(reserveManager.balance(), 0); // 物理储备被坏账耗尽

        // 后续计息（bob 仍在借）：储备低于目标 → 无溢出，仅 3% 进 Treasury、5% 重新积累
        uint256 treasuryBefore = pool.treasuryAccrued();
        uint256 borrowsBefore = pool.getTotalBorrows();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        uint256 interest2 = pool.getTotalBorrows() - borrowsBefore;
        assertGt(interest2, 0);
        uint256 target2 = pool.getTotalBorrows() * 1e15 / 1e18;
        assertLt(pool.totalReserve() + reserveManager.balance(), target2); // 仍在积累，未溢出
        assertApproxEqAbs(pool.treasuryAccrued() - treasuryBefore, interest2 * 2e16 / 1e18, 1e6);
        _assertInvariant();
    }

    /// @notice 总借款增加 → 储备目标增加 → 从"溢出"变回"积累"。
    function test_BorrowsIncrease_TargetIncreases_OverflowStops() public {
        _setupBorrow();
        _setLowTarget();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue(); // 溢出中，totalReserve = target
        uint256 reserveBefore = pool.totalReserve();

        // 新借款人 bob 借款 → totalBorrows 增加 → target 上升
        _supplyCollateral(bob, 2 ether);
        _borrow(bob, 3000e6, 5);

        uint256 treasuryBefore = pool.treasuryAccrued();
        uint256 borrowsBefore = pool.getTotalBorrows();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        uint256 interest = pool.getTotalBorrows() - borrowsBefore;
        assertGt(interest, 0);
        // 新 target 高于当前储备 → 无溢出，5% 正常积累、3% 正常进 Treasury
        uint256 targetNew = pool.getTotalBorrows() * 1e15 / 1e18;
        assertLt(pool.totalReserve(), targetNew);
        assertGt(pool.totalReserve(), reserveBefore); // 储备继续积累（未溢出）
        assertApproxEqAbs(pool.treasuryAccrued() - treasuryBefore, interest * 2e16 / 1e18, 1e6);
        _assertInvariant();
    }

    /// @notice 总借款减少 → 储备目标减少 → 可能触发溢出。
    function test_BorrowsDecrease_TargetDecreases_TriggersOverflow() public {
        _setupBorrow();
        _setLowTarget();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue(); // 储备积累中（未达目标）
        uint256 reserveBefore = pool.totalReserve();
        uint256 targetBefore = pool.getTotalBorrows() * 1e15 / 1e18;
        assertLt(reserveBefore, targetBefore);

        // 大幅还款 → totalBorrows 骤降 → target 骤降，储备相对过高
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(2900e6);
        uint256 targetAfter = pool.getTotalBorrows() * 1e15 / 1e18;
        assertLt(targetAfter, reserveBefore);

        uint256 treasuryBefore = pool.treasuryAccrued();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue(); // 仍有借款 → 有利息 → 触发溢出
        assertApproxEqAbs(pool.totalReserve(), pool.getTotalBorrows() * 1e15 / 1e18, 1e6);
        assertGt(pool.treasuryAccrued(), treasuryBefore); // 有溢出进 Treasury
        _assertInvariant();
    }

    /// @notice collectTreasury 正常转账且清零。
    function test_CollectTreasury_TransfersAndClears() public {
        _setupBorrow();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        uint256 treasury = pool.treasuryAccrued();
        assertGt(treasury, 0);

        address treasuryAddr = makeAddr("treasury");
        vm.prank(admin);
        pool.setTreasuryAddress(treasuryAddr);
        uint256 balBefore = usdc.balanceOf(treasuryAddr);
        vm.expectEmit(true, true, true, true);
        emit TreasuryCollected(treasury, treasuryAddr);
        vm.prank(alice); // 任何人可调用
        pool.collectTreasury();

        assertEq(pool.treasuryAccrued(), 0);
        assertEq(usdc.balanceOf(treasuryAddr) - balBefore, treasury);
        _assertInvariant();
    }

    /// @notice treasuryAddress 为零时 collectTreasury revert。
    function test_CollectTreasury_RevertsWhenZeroAddress() public {
        _setupBorrow();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        assertGt(pool.treasuryAccrued(), 0);
        assertEq(pool.treasuryAddress(), address(0));

        vm.prank(alice);
        vm.expectRevert(bytes("treasury not set"));
        pool.collectTreasury();
    }

    /// @notice ReserveOverflowTransferred 事件正确触发。
    function test_ReserveOverflowTransferredEvent() public {
        _setupBorrow();
        _setLowTarget();
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue(); // 已溢出一次

        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        vm.recordLogs();
        pool.accrue();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("ReserveOverflowTransferred(uint256)")) {
                found = true;
            }
        }
        assertTrue(found, "ReserveOverflowTransferred not emitted");
        _assertInvariant();
    }

    /// @notice totalBorrows = 0 时目标为 0，但**不**触发溢出：储备保留，待借款恢复再积累。
    function test_NoBorrows_NoOverflow_ReservePreserved() public {
        _setupBorrow();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        uint256 reserveBefore = pool.totalReserve();
        uint256 treasuryBefore = pool.treasuryAccrued();
        assertGt(reserveBefore, 0);

        // 全部还清 → totalBorrows = 0
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(type(uint256).max);
        assertEq(pool.getTotalBorrows(), 0);

        // 无借款 → 无利息 → 不触发溢出，储备与 treasury 均不变
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        assertEq(pool.totalReserve(), reserveBefore); // 储备保留
        assertEq(pool.treasuryAccrued(), treasuryBefore);
        _assertInvariant();
    }

    /// @notice 固定费率参数取值边界：超 100% 与零地址被拒。
    function test_SetterValueGuards() public {
        vm.prank(admin);
        vm.expectRevert(bytes("ratio>100%"));
        pool.setReserveTargetRatio(1e18 + 1);
        vm.prank(admin);
        vm.expectRevert(bytes("factor>100%"));
        pool.setReserveFactor(1e18 + 1);
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setTreasuryAddress(address(0));

        // 两费率之和不得超过 100%
        vm.prank(admin);
        pool.setReserveFactor(8e17);
        vm.prank(admin);
        vm.expectRevert(bytes("fees>100%"));
        pool.setTreasuryFactor(3e17);
        vm.prank(admin);
        pool.setTreasuryFactor(1e17);
        assertEq(pool.reserveFactor() + pool.treasuryFactor(), 9e17);
        assertEq(pool.depositorShare(), 1e17);
    }
}
