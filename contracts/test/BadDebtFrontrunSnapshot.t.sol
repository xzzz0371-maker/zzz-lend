// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";
import {console2} from "forge-std/console2.sol";

/// @notice 坏账 front-run / bank-run 快照：handleBadDebt 无延迟、无提款锁。
/// 已知权衡（主网准备文档 §遗留问题 7）：价格已崩、借款人已被清算但坏账尚未被
/// handleBadDebt 处理前，存款人可以先行全额提取（front-run 坏账传导），把损失留给
/// 尚未提取的存款人。本文件将这一行为固化为快照：记录坏账落地窗口内的抢先提取、
/// 无人抢先的按份分摊，以及提款受池内现金上限约束的 bank-run 现实限制。
/// ⚠️ 目的不是证明漏洞，而是固化“无延迟提款”的公平性权衡，供治理决策。
contract BadDebtFrontrunSnapshotTest is BaseSetupV2 {
    address internal borrower;

    function setUp() public override {
        BaseSetupV2.setUp();
        borrower = makeAddr("borrower");
        vm.deal(borrower, 1000 ether);
    }

    /// @notice 构造“已清算、残留坏账、尚未 handleBadDebt”的窗口状态（快照 0）。
    function _openBadDebtWindow() internal {
        // 两存款人各存 100_000 USDC（alice/bob 由 BaseSetup 拥有足额测试币）
        _supply(alice, 100_000e6);
        _supply(bob, 100_000e6);

        // 借款人：1 ETH 抵押（3000 USD）→ tier5 借 2400（≈80% LTV）
        _supplyCollateral(borrower, 1 ether);
        _borrow(borrower, 2400e6, 5);

        // 累计 1 年利息：产生储备 + 债务增长（坏账规模更大）
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 1);
        pool.accrue();

        // ETH 崩盘 → 清算清空抵押、留下残余债务（坏账窗口打开）
        oracle.setPrice(ETH, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        uint256 guard = 0;
        while (pool.userCollateralOf(borrower, C_ETH) > 0 && guard < 6) {
            vm.prank(liquidator);
            pool.liquidate(borrower, M_USDC, ETH, type(uint256).max, 0);
            guard++;
        }
        assertEq(pool.userCollateralOf(borrower, C_ETH), 0, "collateral must be empty");
        assertGt(pool.userDebtToken(borrower, M_USDC), 0, "no residual bad debt");
    }

    function _depositorValue(address who) internal view returns (uint256) {
        return pool.userSharesOf(who, M_USDC) * pool.supplyIndex() / 1e18;
    }

    function _writeSnapshot(string memory tag) internal view {
        (uint256 cash, uint256 borrows, uint256 supply, uint256 reserve, uint256 treasury,) =
            pool.marketAccounts(M_USDC);
        console2.log("== snapshot tag ==");
        console2.log(tag);
        console2.log("cash:", cash);
        console2.log("borrows:", borrows);
        console2.log("supply:", supply);
        console2.log("reserve:", reserve);
        console2.log("treasury:", treasury);
        console2.log("alice-value:", _depositorValue(alice));
        console2.log("bob-value:", _depositorValue(bob));
    }

    /// @notice 快照：窗口内 front-run 提取者（bob）全额提走；handleBadDebt 后剩余存款人承担损耗。
    function test_FrontrunWithdrawEscapesLoss_RemainingBearsIt() public {
        _openBadDebtWindow();
        _writeSnapshot("window-open");

        uint256 bobShares = pool.userSharesOf(bob, M_USDC);
        uint256 bobValueBefore = _depositorValue(bob);

        // bob 在坏账落地前全额提取（拿回自己份额现值）
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        pool.withdraw(M_USDC, bobShares);
        assertEq(usdc.balanceOf(bob) - bobBalanceBefore, bobValueBefore, "front-run withdraw must be full value");
        _writeSnapshot("after-frontrun-withdraw");

        uint256 supplyIndexBefore = pool.supplyIndex();
        vm.prank(address(0xdead));
        pool.handleBadDebt(borrower, M_USDC);
        _writeSnapshot("after-handleBadDebt");

        // 坏账传导使 supplyIndex 下降 → 剩余存款人 alice 承担损耗
        assertLt(pool.supplyIndex(), supplyIndexBefore, "supplyIndex must drop after bad debt");
        assertLt(_depositorValue(alice), 100_000e6, "remaining depositor must bear loss");
        assertGt(_depositorValue(alice), 0);
        _assertMarketConservationApprox(M_USDC, 1e6);
    }

    /// @notice 对照快照：无人 front-run（直接 handleBadDebt）→ 两存款人按份额分摊损失。
    function test_NoFrontrun_BothDepositorsShareProportionally() public {
        _openBadDebtWindow();
        _writeSnapshot("window-open");

        uint256 aliceValueBefore = _depositorValue(alice);
        uint256 bobValueBefore = _depositorValue(bob);
        vm.prank(address(0xdead));
        pool.handleBadDebt(borrower, M_USDC);
        _writeSnapshot("after-handleBadDebt");

        uint256 aliceAfter = _depositorValue(alice);
        uint256 bobAfter = _depositorValue(bob);
        // 相同份额 → 相同绝对损失，按比例承担
        assertApproxEqAbs(aliceValueBefore - aliceAfter, bobValueBefore - bobAfter, 1e6, "loss must be proportional");
        assertLt(aliceAfter, aliceValueBefore);
        assertLt(bobAfter, bobValueBefore);
        _assertMarketConservationApprox(M_USDC, 1e6);
    }

    /// @notice 快照恢复：同一坏账窗口可反复处理，且无残留副作用（幂等）。
    function test_BadDebtHandlingRepeatable_SnapshotRestore() public {
        _openBadDebtWindow();
        uint256 snap = vm.snapshotState();

        vm.prank(address(0xdead));
        pool.handleBadDebt(borrower, M_USDC);
        (uint256 cash1, uint256 borrows1, uint256 supply1,,,) = pool.marketAccounts(M_USDC);

        vm.revertToState(snap);
        // 恢复后仍是未处理状态：可再次 handleBadDebt，结果一致（确定性，无残留状态依赖）
        vm.prank(address(0xdead));
        pool.handleBadDebt(borrower, M_USDC);
        (uint256 cash2, uint256 borrows2, uint256 supply2,,,) = pool.marketAccounts(M_USDC);
        assertEq(cash2, cash1);
        assertEq(borrows2, borrows1);
        assertEq(supply2, supply1);
        _assertMarketConservationApprox(M_USDC, 1e6);
    }

    /// @notice bank-run 的现实约束：坏账窗口内提取受池现金上限保护，超额请求 revert。
    function test_BankrunLimitedByCash_FrontrunAfterLiquidation() public {
        _openBadDebtWindow();
        uint256 cash = _marketCash(M_USDC);
        uint256 bobShares = pool.userSharesOf(bob, M_USDC);
        uint256 bobValue = _depositorValue(bob);
        if (bobValue > cash) {
            vm.prank(bob);
            vm.expectRevert(bytes("insufficient liquidity"));
            pool.withdraw(M_USDC, bobShares);
        } else {
            vm.prank(bob);
            pool.withdraw(M_USDC, bobShares);
        }
        _assertMarketConservationApprox(M_USDC, 1e6);
    }
}
