// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

/// @notice 坏账即时传导给存款人：先由风险储备（第一损失缓冲）覆盖，未覆盖部分即时降低 supplyIndex，
///         存款人按份额承担损失。不挂账、无 settleBadDebt。
contract BadDebtTest is BaseSetup {
    event BadDebtRealized(
        address indexed user,
        uint256 badDebtAmount,
        uint256 coveredByReserve,
        uint256 lossToDepositors,
        uint256 oldSupplyIndex,
        uint256 newSupplyIndex
    );

    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }

    /// @notice 构造坏账仓位：抵押归零仍有债务。返回剩余债务（USDC 单位）。
    function _setupBadDebt(uint256 supplyAmount) internal returns (uint256 badDebt6) {
        _supply(bob, supplyAmount);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2400e6, 5);
        oracle.setPrice(ETH, 1e8); // 抵押价值归零
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10_000e6, 0); // 清空抵押
        (, uint256 collAfter,,,,,) = pool.getUserPosition(alice);
        assertEq(collAfter, 0);
        badDebt6 = pool.getDebt(alice) / 1e12;
        assertGt(badDebt6, 0);
    }

    /// @notice 储备充足：坏账全部由储备覆盖，supplyIndex 不变，存款人不受影响。
    function test_ReserveSufficient_SupplyIndexUnchanged() public {
        uint256 badDebt = _setupBadDebt(200_000e6);
        usdc.transfer(address(reserveManager), 10_000e6); // 储备远大于坏账
        assertGt(10_000e6, badDebt);

        uint256 supplyIndexBefore = pool.supplyIndex();
        uint256 supplyBefore = pool.getTotalSupply();
        uint256 reserveBefore = reserveManager.balance();
        uint256 cashBefore = pool.cash();

        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);

        assertEq(pool.supplyIndex(), supplyIndexBefore); // supplyIndex 不变
        assertEq(pool.getTotalSupply(), supplyBefore); // 存款人不受影响
        assertEq(pool.getDebt(alice), 0); // 仓位清零
        assertApproxEqAbs(reserveBefore - reserveManager.balance(), badDebt, 1e6); // 储备全额覆盖
        assertApproxEqAbs(pool.cash() - cashBefore, badDebt, 1e6); // 储备资金回到池
        _assertInvariant();
    }

    /// @notice 储备不足：储备覆盖部分，剩余部分降低 supplyIndex，存款人承担损失。
    function test_ReserveInsufficient_DepositorsBearLoss() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2400e6, 5);
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();
        pool.skimReserve(); // 小额储备缓冲
        uint256 reserveSeeded = reserveManager.balance();
        assertGt(reserveSeeded, 0);

        oracle.setPrice(ETH, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10_000e6, 0);
        uint256 badDebt = pool.getDebt(alice) / 1e12;
        assertGt(badDebt, reserveSeeded); // 坏账 > 储备

        uint256 supplyIndexBefore = pool.supplyIndex();
        uint256 supplyBefore = pool.getTotalSupply();
        uint256 treasuryBefore = pool.treasuryAccrued();
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);

        assertEq(reserveManager.balance(), 0); // 物理储备耗尽
        uint256 covered6 = reserveSeeded;
        uint256 loss6 = badDebt - covered6;
        assertGt(loss6, 0);
        assertLt(pool.supplyIndex(), supplyIndexBefore);
        assertApproxEqAbs(pool.getTotalSupply(), supplyBefore - loss6, 1e6); // 存款人承担（书面储备=0）
        assertEq(pool.treasuryAccrued(), treasuryBefore); // Treasury 最后：本案不动
        _assertInvariant();
    }

    /// @notice 储备为零：坏账全额降低 supplyIndex，存款人全额承担。
    function test_ReserveZero_FullLossToDepositors() public {
        uint256 badDebt = _setupBadDebt(200_000e6);
        assertEq(reserveManager.balance(), 0);

        uint256 supplyIndexBefore = pool.supplyIndex();
        uint256 supplyBefore = pool.getTotalSupply();
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);

        assertEq(pool.getDebt(alice), 0);
        assertEq(reserveManager.balance(), 0);
        assertLt(pool.supplyIndex(), supplyIndexBefore);
        assertApproxEqAbs(pool.getTotalSupply(), supplyBefore - badDebt, 1e6); // 全额传导
        _assertInvariant();
    }

    /// @notice 多存款人：两人各存 50%，坏账后份额净值等比例（相同）下降。
    function test_MultipleDepositors_ProportionalLoss() public {
        _supply(alice, 100_000e6);
        _supply(bob, 100_000e6);
        address carol = makeAddr("carol");
        vm.deal(carol, 1000 ether);
        vm.prank(carol);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(carol);
        pool.borrow(0, 2400e6, 5);

        oracle.setPrice(ETH, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(carol, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10_000e6, 0);

        (uint256 aliceShares,,,,,,) = pool.getUserPosition(alice);
        (uint256 bobShares,,,,,,) = pool.getUserPosition(bob);
        assertApproxEqAbs(aliceShares, bobShares, 1e6); // 各 50%

        uint256 supplyIndexBefore = pool.supplyIndex();
        vm.prank(address(0xdead));
        pool.handleBadDebt(carol, 0);

        assertLt(pool.supplyIndex(), supplyIndexBefore);
        uint256 aliceValue = aliceShares * pool.supplyIndex() / 1e18;
        uint256 bobValue = bobShares * pool.supplyIndex() / 1e18;
        assertApproxEqAbs(aliceValue, bobValue, 1e6); // 等比例（相同份额）下降
        assertLt(aliceValue, 100_000e6); // 双双受损
        assertLt(bobValue, 100_000e6);
        _assertInvariant();
    }

    /// @notice 坏账后取款：supplyIndex 下降后，取款金额正确减少。
    function test_WithdrawAfterBadDebt_AmountReduced() public {
        _setupBadDebt(200_000e6);
        (uint256 bobShares,,,,,,) = pool.getUserPosition(bob);
        uint256 supplyIndexBefore = pool.supplyIndex();

        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);

        uint256 half = bobShares / 2;
        uint256 expectedNow = half * pool.supplyIndex() / 1e18;
        uint256 expectedBefore = half * supplyIndexBefore / 1e18;
        assertGt(expectedBefore, expectedNow); // 坏账后取款金额减少

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        pool.withdraw(0, half);
        assertEq(usdc.balanceOf(bob) - bobBalanceBefore, expectedNow); // 按新 supplyIndex 取款
        _assertInvariant();
    }

    /// @notice 坏账后利息累计：supplyIndex 已下降，后续利息基于新的 supplyIndex 正常累计。
    function test_AccrueAfterBadDebt_UsesNewSupplyIndex() public {
        _setupBadDebt(400_000e6);
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);
        uint256 supplyIndexAfterBadDebt = pool.supplyIndex();
        uint256 supplyAfterBadDebt = pool.getTotalSupply();
        assertEq(pool.getTotalBorrows(), 0); // 唯一借款已清

        // 新借款人进入，后续利息继续累计
        oracle.setPrice(ETH, 3000e8); // 恢复价格
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 1000e6, 5);
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();

        uint256 supplyGain = pool.getTotalSupply() - supplyAfterBadDebt;
        uint256 interest = pool.getTotalBorrows() - 1000e6;
        assertGt(interest, 0);
        assertApproxEqAbs(supplyGain, interest * 9 / 10, 1e6); // 储备未达标阶段：90% 归存款人
        assertGt(pool.supplyIndex(), supplyIndexAfterBadDebt);
        _assertInvariant();
    }

    /// @notice 管理员无法直接降低 supplyIndex：不存在公开 setter，只能经 handleBadDebt 触发。
    function test_AdminCannotChangeSupplyIndexDirectly() public {
        _supply(bob, 100_000e6);
        uint256 supplyIndexBefore = pool.supplyIndex();

        vm.prank(admin);
        pool.setReserveTargetRatio(3e16);
        vm.prank(admin);
        pool.setTreasuryAddress(makeAddr("treasury"));

        (bool ok,) = address(pool).call(abi.encodeWithSignature("setSupplyIndex(uint256)", 1));
        assertFalse(ok); // 低层调用不存在的 setter 必须失败
        assertEq(pool.supplyIndex(), supplyIndexBefore);
        _assertInvariant();
    }

    /// @notice 零坏账：健康仓位或有抵押时 handleBadDebt revert，不改变任何状态。
    function test_ZeroBadDebt_NoStateChange() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 5);

        vm.prank(address(0xdead));
        vm.expectRevert(bytes("collateral exists"));
        pool.handleBadDebt(alice, 0);

        vm.prank(address(0xdead));
        vm.expectRevert(bytes("no debt"));
        pool.handleBadDebt(bob, 0);

        assertEq(pool.supplyIndex(), 1e18);
        assertEq(pool.getTotalSupply(), 100_000e6);
        _assertInvariant();
    }

    /// @notice BadDebtRealized 事件参数正确。
    function test_BadDebtRealizedEvent() public {
        uint256 badDebt = _setupBadDebt(200_000e6);
        uint256 supplyBefore = pool.getTotalSupply();
        uint256 supplyIndexBefore = pool.supplyIndex();
        uint256 expectedNewIndex = supplyIndexBefore * (supplyBefore - badDebt) / supplyBefore;

        vm.expectEmit(true, true, true, true);
        emit BadDebtRealized(alice, badDebt, 0, badDebt, supplyIndexBefore, expectedNewIndex);
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);
        assertEq(pool.supplyIndex(), expectedNewIndex);
        _assertInvariant();
    }
}
