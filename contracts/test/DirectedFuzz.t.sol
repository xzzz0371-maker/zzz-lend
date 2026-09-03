// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";

/// @notice 定向 fuzz：repay / liquidate 金额在合法区间（含边界）不越界：
///         - repay：部分还款债务降幅≈还款额；全额/超额一律清零、无取整残留；
///         - liquidate：cover 不超过 closeFactor×原债务、seize 不为 0 且有上限、守恒；
///         - 多市场/多抵押组合与连续清算直到清仓或坏账。
contract DirectedFuzzTest is BaseSetupV2 {
    // WAD 已由 BaseSetup 提供（1e18）。

    function _assertConservedApprox(uint8 m) internal view {
        _assertMarketConservationApprox(m, m == M_DAI ? 1e15 : 1e6);
    }

    // ==================== repay 定向 fuzz ====================

    /// @notice 部分还款：repay ∈ (0, debt)。债务下降≈还款额；守恒成立。
    function testFuzz_RepayPartialAlwaysWithinBounds(uint256 repayUsd) public {
        _supply(bob, 500_000e6);
        _supplyCollateral(alice, 2 ether); // 6000 USD
        _borrow(alice, 1000e6, 5);

        uint256 debtBefore = pool.userDebtToken(alice, M_USDC);
        repayUsd = bound(repayUsd, 1, debtBefore / 1e6 - 1);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_USDC, repayUsd * 1e6);

        uint256 debtAfter = pool.userDebtToken(alice, M_USDC);
        uint256 expect = debtBefore - repayUsd * 1e6;
        assertTrue(_approx(debtAfter, expect, 1e6), "partial repay delta broken");
        assertEq(uint256(pool.userGlobalTier(alice)), 5, "partial repay must keep tier");
        _assertConservedApprox(M_USDC);
    }

    /// @notice 全额/超额还款：repay ≥ debt（计息后）一律清零，不残留取整尘埃。
    function testFuzz_RepayOverDebtClearsEverything(uint256 extraUsd) public {
        _supply(bob, 500_000e6);
        _supplyCollateral(alice, 3 ether); // 9000
        _borrow(alice, 3000e6, 5);
        vm.warp(block.timestamp + 400 days);
        pool.accrue();
        uint256 debtRaw = pool.userDebtToken(alice, M_USDC);
        assertGt(debtRaw, 3000e6);
        extraUsd = bound(extraUsd, 0, 1_000_000);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_USDC, debtRaw + extraUsd * 1e6); // ≥ debt
        assertEq(pool.userDebtToken(alice, M_USDC), 0);
        assertEq(uint256(pool.userGlobalTier(alice)), 0);
        assertEq(_marketBorrows(M_USDC), 0);
        _assertConservedApprox(M_USDC);
    }

    /// @notice 跨市场 repay：DAI（18 位）部分/全额还款边界。
    function testFuzz_RepayDaiFullAndPartial(uint256 repayDai) public {
        _supplyMarket(address(dai), M_DAI, bob, 500_000e18);
        _supplyCollateral(alice, 10 ether); // 30_000 USD
        _borrowMarket(M_DAI, alice, 4000e18, 1);
        repayDai = bound(repayDai, 1, 50_000);
        _approveToken(address(dai), alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_DAI, repayDai * 1e18);
        if (repayDai >= 4000) {
            assertEq(pool.userDebtToken(alice, M_DAI), 0, "full repay should clear");
        } else {
            uint256 expect = (4000 - repayDai) * 1e18;
            assertTrue(_approx(pool.userDebtToken(alice, M_DAI), expect, 1e12), "partial dai repay broken");
        }
        _assertConservedApprox(M_DAI);
        _assertMarketConservation(M_USDC);
    }

    // ==================== liquidate 定向 fuzz ====================

    /// @notice 单笔 cover：无论申请额多大都不超过 closeFactor×债务；cover>0；守恒。
    function testFuzz_LiquidateCoverCappedAtCloseFactor(uint256 coverUsd, uint256 priceDropPct) public {
        priceDropPct = bound(priceDropPct, 30, 90);
        _supply(bob, 500_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 3000e8 * (100 - priceDropPct) / 100);
        assertTrue(pool.isLiquidatable(alice), "not liquidatable");

        coverUsd = bound(coverUsd, 1, 200_000);
        uint256 debtRaw = pool.userDebtToken(alice, M_USDC);
        uint256 cashBefore = _marketCash(M_USDC);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDC, ETH, coverUsd * 1e6, 0);

        uint256 paid = _marketCash(M_USDC) - cashBefore;
        assertGt(paid, 0, "no cover");
        assertLe(paid, debtRaw, "cover paid exceeds debt");
        uint256 closeFactor = riskManager.getCloseFactor();
        assertLe(paid, debtRaw * closeFactor / WAD + 1e6, "cover exceeds closeFactor cap");
        _assertConservedApprox(M_USDC);
    }

    /// @notice 清算不产生零 seize：可清算时任意合理 cover 都有抵押可收；守恒。
    function testFuzz_LiquidateAlwaysSeizesSomething(uint256 coverUsd, uint256 pricePct) public {
        pricePct = bound(pricePct, 30, 55); // 需 3000·pct·0.9 < 1500 → pct<55.6%
        _supply(bob, 500_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrow(alice, 1500e6, 5);
        oracle.setPrice(ETH, 3000e8 * pricePct / 100);
        assertTrue(pool.isLiquidatable(alice), "should be liquidatable");

        coverUsd = bound(coverUsd, 1, 10_000);
        uint256 collBefore = pool.userCollateralOf(alice, C_ETH);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDC, ETH, coverUsd * 1e6, 0);
        uint256 seized = collBefore - pool.userCollateralOf(alice, C_ETH);
        assertGt(seized, 0, "must seize something");
        assertLe(seized, collBefore, "cannot seize more than held");
        _assertConservedApprox(M_USDC);
    }

    /// @notice 多市场/多抵押清算：WBTC 抵押、USDT 债务，cover 随机；两市场守恒。
    function testFuzz_LiquidateCrossMarketCover(uint256 coverUsd, uint256 wbtcPricePct) public {
        wbtcPricePct = bound(wbtcPricePct, 30, 80); // 需 1000·pct·0.85 < 700 → pct<82%
        _supplyMarket(address(usdt), M_USDT, bob, 500_000e6);
        _supplyCollateralAsset(address(wbtc), alice, 0.01e8); // 1000 USD @100k
        _borrowMarket(M_USDT, alice, 700e6, 5);
        oracle.setPrice(address(wbtc), 100_000e8 * wbtcPricePct / 100);
        assertTrue(pool.isLiquidatable(alice), "cross-market not liquidatable");

        coverUsd = bound(coverUsd, 1, 3000);
        uint256 debtRaw = pool.userDebtToken(alice, M_USDT);
        uint256 cashBefore = _marketCash(M_USDT);
        _approveToken(address(usdt), liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDT, address(wbtc), coverUsd * 1e6, 0);
        uint256 paid = _marketCash(M_USDT) - cashBefore;
        assertGt(paid, 0);
        assertLe(paid, debtRaw);
        _assertConservedApprox(M_USDT);
        _assertMarketConservation(M_USDC);
    }

    // ==================== 组合：连续清算直到清仓/坏账 ====================

    /// @notice 深度崩盘下反复清算直到抵押清空或债务清零：全程守恒、不产生金额下溢。
    function testFuzz_LiquidationRunsUntilClean(uint256 coverUsd) public {
        // cover×1.05 ≥ 抵押现值(150 USD) → 单笔即清空抵押：cover ∈ [143, 500]
        coverUsd = bound(coverUsd, 143, 500);
        _supply(bob, 500_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2400e6, 5);
        oracle.setPrice(ETH, 150e8); // 150 USD → 抵押价值 150 << 债务
        assertTrue(pool.isLiquidatable(alice));

        _approveUsdc(liquidator, type(uint256).max);
        uint256 guard = 0;
        while (pool.userCollateralOf(alice, C_ETH) > 0 && pool.isLiquidatable(alice) && guard < 10) {
            vm.prank(liquidator);
            pool.liquidate(alice, M_USDC, ETH, coverUsd * 1e6, 0);
            guard++;
            _assertConservedApprox(M_USDC);
        }
        (, uint256 collLeft, uint256 debtWadLeft,,,,) = pool.getUserPosition(alice);
        assertTrue(collLeft == 0 || debtWadLeft == 0 || !pool.isLiquidatable(alice), "loop stopped unexpectedly");
        if (collLeft == 0 && debtWadLeft > 0) {
            pool.handleBadDebt(alice, M_USDC);
            assertEq(pool.getDebt(alice), 0);
        }
        _assertConservedApprox(M_USDC);
    }

    // ==================== helpers ====================

    function _approx(uint256 a, uint256 b, uint256 tol) internal pure returns (bool) {
        return a >= b ? (a - b) <= tol : (b - a) <= tol;
    }
}
