// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// @notice V2 多资产/多市场测试：每资产 supply/borrow/repay/withdraw/liquidate + 跨抵押 × 跨市场组合。
contract MultiAssetTest is BaseSetupV2 {
    // ==================== 注册 ====================

    function test_MarketsAndCollateralsRegistered() public {
        // Risk 参数：WBTC 保守档位 / wstETH 同 ETH
        assertEq(riskManager.getMaxLTV(address(wbtc), 5), 75e16);
        assertEq(riskManager.getLiquidationThreshold(address(wbtc), 5), 85e16);
        assertEq(riskManager.getMaxLTV(address(wsteth), 5), 8e17);
        assertEq(riskManager.getMaxLTV(address(wsteth), 1), 5e17);
        // 功能验证：每个市场/抵押品可用
        _supplyMarket(address(usdt), M_USDT, bob, 10_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 10_000e18);
        _supplyCollateral(alice, 1 ether);
        _borrowMarket(M_USDT, alice, 500e6, 1);
        assertGt(pool.userDebtToken(alice, M_USDT), 0);
    }

    function test_DuplicateMarketAndCollateralRejected() public {
        vm.prank(admin);
        vm.expectRevert(bytes("market exists"));
        pool.addMarket(address(usdt), 6);
        vm.prank(admin);
        vm.expectRevert(bytes("collateral exists"));
        pool.addCollateral(address(wbtc), 8);
    }

    // ==================== USDT 市场（6 位） ====================

    function test_UsdtSupplyBorrowRepayWithdraw() public {
        _supplyMarket(address(usdt), M_USDT, bob, 100_000e6);
        assertEq(pool.userSharesOf(bob, M_USDT), 100_000e6);
        _supplyCollateral(alice, 2 ether); // 6000 USD
        _borrowMarket(M_USDT, alice, 1500e6, 2);
        assertEq(pool.userDebtToken(alice, M_USDT), 1500e6);
        assertGt(_marketBorrows(M_USDT), 0);
        assertEq(_marketBorrows(M_USDC), 0); // 市场隔离
        _assertMarketConservation(M_USDT);

        // 部分还款
        _approveToken(address(usdt), alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_USDT, 500e6);
        assertEq(pool.userDebtToken(alice, M_USDT), 1000e6);
        // 全还清
        vm.prank(alice);
        pool.repay(M_USDT, type(uint256).max);
        assertEq(pool.userDebtToken(alice, M_USDT), 0);
        assertEq(pool.getDebt(alice), 0);
        _assertMarketConservation(M_USDT);

        // 取款
        uint256 bobSharesUsdt = pool.userSharesOf(bob, M_USDT);
        vm.prank(bob);
        pool.withdraw(M_USDT, bobSharesUsdt);
        assertEq(_marketSupply(M_USDT), 0);
        assertEq(usdt.balanceOf(bob), 500_000e6); // 回到初始全额
        _assertMarketConservation(M_USDT);
    }

    function test_UsdtLiquidationSeizesEth() public {
        _supplyMarket(address(usdt), M_USDT, bob, 100_000e6);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrowMarket(M_USDT, alice, 2000e6, 5); // HF = 3000*0.9/2000 = 1.35
        oracle.setPrice(ETH, 2000e8); // 抵押值 2000 → HF=0.9
        _approveToken(address(usdt), liquidator, type(uint256).max);
        uint256 collBefore = pool.userCollateralOf(alice, C_ETH);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDT, ETH, 1000e6, 0);
        assertGt(collBefore - pool.userCollateralOf(alice, C_ETH), 0);
        assertLt(pool.userDebtToken(alice, M_USDT), 2000e6);
        _assertMarketConservation(M_USDT);
    }

    // ==================== DAI 市场（18 位） ====================

    function test_DaiSupplyBorrowRepay() public {
        _supplyMarket(address(dai), M_DAI, bob, 100_000e18);
        _supplyCollateral(alice, 1 ether); // 3000
        _borrowMarket(M_DAI, alice, 1000e18, 1);
        assertEq(pool.userDebtToken(alice, M_DAI), 1000e18);
        assertEq(_marketBorrows(M_DAI), 1000e18);
        assertEq(_marketBorrows(M_USDC), 0);
        assertEq(_marketBorrows(M_USDT), 0);
        // HF：抵押 3000 USD × LT60% / 债务 1000 = 1.8
        assertApproxEqAbs(pool.getUserHealthFactor(alice), 18e17, 1e12);
        _assertMarketConservation(M_DAI);

        _approveToken(address(dai), alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_DAI, type(uint256).max);
        assertEq(pool.userDebtToken(alice, M_DAI), 0);
        assertEq(pool.getDebt(alice), 0);
        _assertMarketConservation(M_DAI);

        uint256 bobSharesDai = pool.userSharesOf(bob, M_DAI);
        vm.prank(bob);
        pool.withdraw(M_DAI, bobSharesDai);
        assertEq(_marketSupply(M_DAI), 0);
        assertEq(dai.balanceOf(bob), 500_000e18); // 回到初始全额
    }

    function test_DaiDecimalsMinAmounts() public {
        _supplyCollateral(alice, 1 ether);
        // DAI min borrow = 100 整 token
        vm.expectRevert(bytes("amount below min"));
        _borrowMarket(M_DAI, alice, 99e18, 1);
        // USDC min borrow = 100e6（默认市场）
        vm.expectRevert(bytes("amount below min"));
        pool.borrow(0, 99e6, 1);
        // DAI min supply = 10 整 token
        _approveToken(address(dai), alice, 10e18);
        vm.prank(alice);
        vm.expectRevert(bytes("amount below min"));
        pool.supply(M_DAI, 10e18 - 1);
        _supplyMarket(address(dai), M_DAI, alice, 10e18); // min supply 通过
        _supplyMarket(address(dai), M_DAI, bob, 2000e18); // 提供 DAI 现金
        vm.prank(alice);
        pool.borrow(M_DAI, 100e18, 1);
        assertEq(pool.userDebtToken(alice, M_DAI), 100e18);
    }

    // ==================== wstETH 抵押（1:1 ETH 锚定） ====================

    function test_WstethCollateralBorrowUsdc() public {
        _supply(bob, 200_000e6);
        _supplyCollateralAsset(address(wsteth), alice, 1 ether); // 3000 USD
        uint256 maxB = pool.maxBorrowable(alice, 5);
        assertEq(maxB, 2400e6); // 80%
        _borrow(alice, 1500e6, 5);
        assertApproxEqAbs(pool.getUserHealthFactor(alice), 18e17, 1e12); // 3000*0.9/1500
        _assertMarketConservation(M_USDC);
        // 取回 wstETH 不能低于健康
        vm.prank(alice);
        vm.expectRevert(bytes("unhealthy"));
        pool.withdrawCollateral(address(wsteth), 1 ether);
    }

    function test_WstethLiquidationSeizesWsteth() public {
        _supply(bob, 200_000e6);
        _supplyCollateralAsset(address(wsteth), alice, 1 ether);
        _borrow(alice, 1500e6, 5); // HF 1.8
        oracle.setPrice(address(wsteth), 1500e8); // 抵押值 1500 → HF=0.9
        assertTrue(pool.isLiquidatable(alice));
        _approveUsdc(liquidator, type(uint256).max);
        uint256 collBefore = pool.userCollateralOf(alice, C_WSTETH);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDC, address(wsteth), 600e6, 0);
        uint256 seized = collBefore - pool.userCollateralOf(alice, C_WSTETH);
        assertGt(seized, 0);
        assertGt(wsteth.balanceOf(liquidator), 0);
        assertLt(pool.getDebt(alice), 1500e18);
        _assertMarketConservation(M_USDC);
    }

    // ==================== WBTC 抵押（8 位） ====================

    function test_WbtcCollateralBorrowCapacity() public {
        _supply(bob, 200_000e6);
        _supplyCollateralAsset(address(wbtc), alice, 1e8); // 100_000 USD
        // 保守档位 tier5 maxLTV 75% → 75_000
        assertEq(pool.maxBorrowable(alice, 5), 75_000e6);
        _borrow(alice, 70_000e6, 5);
        // HF = 100000 × 85% / 70000 ≈ 1.2143
        uint256 expect = 85_000e18 * WAD / 70_000e18;
        assertApproxEqAbs(pool.getUserHealthFactor(alice), expect, 1e12);
        _assertMarketConservation(M_USDC);
    }

    function test_WbtcLiquidationSeizesWbtc() public {
        _supply(bob, 200_000e6);
        _supplyCollateralAsset(address(wbtc), alice, 1e8);
        _borrow(alice, 70_000e6, 5);
        oracle.setPrice(address(wbtc), 60_000e8); // 抵押值 60_000 → HF=60000*0.85/70000=0.728
        assertTrue(pool.isLiquidatable(alice));
        _approveUsdc(liquidator, type(uint256).max);
        uint256 collBefore = pool.userCollateralOf(alice, C_WBTC);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDC, address(wbtc), 30_000e6, 0);
        uint256 seized = collBefore - pool.userCollateralOf(alice, C_WBTC);
        assertGt(seized, 0);
        assertGt(wbtc.balanceOf(liquidator), 0);
        _assertMarketConservation(M_USDC);
    }

    // ==================== 跨抵押品合计能力/健康度 ====================

    function test_CrossCollateralCapacityAndHealth() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 0.5 ether); // 1500
        _supplyCollateralAsset(address(wbtc), alice, 0.02e8); // 2000
        // tier2：ETH 60% × 1500 + WBTC 55% × 2000 = 900 + 1100 = 2000
        assertApproxEqAbs(pool.maxBorrowable(alice, 2), 2000e6, 1);
        _borrow(alice, 2000e6, 2);
        // LT 加权：1500*0.7 + 2000*0.65 = 1050+1300=2350 / 2000 = 1.175
        assertApproxEqAbs(pool.getUserHealthFactor(alice), 1175e15, 1e12);
        vm.expectRevert(bytes("ltv too high"));
        _borrow(alice, 100e6, 2);
        _assertMarketConservation(M_USDC);
    }

    function test_CombinedCollateralBorrowTier2() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 0.5 ether); // 1500
        _supplyCollateralAsset(address(wsteth), alice, 0.5 ether); // 1500
        _borrow(alice, 1700e6, 2); // cap 60%×3000 = 1800 → ok
        // HF = (1500*0.7 + 1500*0.7)/1700
        uint256 expect1 = 2100e18 * WAD / 1700e18;
        assertApproxEqAbs(pool.getUserHealthFactor(alice), expect1, 1e12);
        // 单提一种会不健康则整体拦截
        vm.prank(alice);
        vm.expectRevert(bytes("unhealthy"));
        pool.withdrawCollateral(address(wsteth), 0.5 ether);
        // 提走小额 ETH 仍健康：剩 0.4 ETH + 0.5 wstETH → (0.4*3000+1500)*0.7/1700
        vm.prank(alice);
        pool.withdrawCollateral(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 0.1 ether);
        uint256 expect2 = 1890e18 * WAD / 1700e18;
        assertApproxEqAbs(pool.getUserHealthFactor(alice), expect2, 1e12);
    }

    // ==================== 跨市场借款（同 tier）+ 逐市场隔离 ====================

    function test_MultiMarketBorrowTierLockAndIsolation() public {
        _supply(bob, 500_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 500_000e18);
        _supplyMarket(address(usdt), M_USDT, bob, 500_000e6);
        _supplyCollateral(alice, 1 ether); // 3000, tier1 cap 1500
        _borrowMarket(M_USDC, alice, 800e6, 1);
        _borrowMarket(M_DAI, alice, 500e18, 1); // total 1300 ≤ 1500
        vm.expectRevert(bytes("tier locked"));
        _borrowMarket(M_USDT, alice, 100e6, 2);
        assertEq(_marketBorrows(M_USDC), 800e6);
        assertEq(_marketBorrows(M_DAI), 500e18);
        assertEq(_marketBorrows(M_USDT), 0);
        // HF = 3000×60% / 1300
        uint256 expectHf = 1800e18 * WAD / 1300e18;
        assertApproxEqAbs(pool.getUserHealthFactor(alice), expectHf, 1e12);
        _assertMarketConservation(M_USDC);
        _assertMarketConservation(M_DAI);

        // 还清 USDC：DAI 债务不受影响，global tier 保留
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(0, type(uint256).max);
        assertEq(_marketBorrows(M_USDC), 0);
        assertEq(pool.userDebtToken(alice, M_DAI), 500e18);
        assertEq(uint256(pool.userGlobalTier(alice)), 1);
        vm.expectRevert(bytes("tier locked"));
        _borrowMarket(M_USDT, alice, 100e6, 3);
        _assertMarketConservation(M_USDC);
    }

    function test_MultiMarketCrossLiquidation() public {
        _supply(bob, 500_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 500_000e18);
        _supplyCollateral(alice, 0.5 ether); // 1500
        _supplyCollateralAsset(address(wsteth), alice, 0.4 ether); // 1200
        _borrowMarket(M_DAI, alice, 1800e18, 5); // cap 80%×2700=2160
        oracle.setPrice(ETH, 2000e8); // ETH 1000
        oracle.setPrice(address(wsteth), 1500e8); // wstETH 600 → 加权 LT = 1000*.9+600*.9=1440/1800=0.8
        assertTrue(pool.isLiquidatable(alice));
        _approveToken(address(dai), liquidator, type(uint256).max);
        uint256 collBefore = pool.userCollateralOf(alice, C_ETH);
        uint256 ethBefore = liquidator.balance;
        vm.prank(liquidator);
        pool.liquidate(alice, M_DAI, ETH, 300e18, 0); // 收 ETH 抵押品
        assertLt(pool.userCollateralOf(alice, C_ETH), collBefore);
        assertGt(liquidator.balance - ethBefore, 0); // 清算人收到 ETH
        _assertMarketConservation(M_DAI);
    }

    // ==================== 坏账逐市场隔离 ====================

    function test_BadDebtIsolatedToDaiMarket() public {
        // bob 只存 DAI，alice 用 wstETH 借 DAI
        _supplyMarket(address(dai), M_DAI, bob, 200_000e18);
        _supplyCollateralAsset(address(wsteth), alice, 1 ether); // 3000
        _borrowMarket(M_DAI, alice, 2400e18, 5);
        // 计提利息（储备留在池内账面）
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        _assertMarketConservationApprox(M_DAI, 1e15); // 大份额市场计息后存在 ≤shares/WAD 取整余数
        uint256 usdcCashBefore = _marketCash(M_USDC);

        // wstETH 崩盘 → 清走全部抵押
        oracle.setPrice(address(wsteth), 1e8);
        _approveToken(address(dai), liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, M_DAI, address(wsteth), type(uint256).max, 0);
        uint256 wstethColl = pool.userCollateralOf(alice, C_WSTETH);
        if (wstethColl > 0) {
            vm.prank(liquidator);
            pool.liquidate(alice, M_DAI, address(wsteth), type(uint256).max, 0);
        }
        // 若仍留抵押，靠更低位再清一次
        while (pool.userCollateralOf(alice, C_WSTETH) > 0) {
            vm.prank(liquidator);
            pool.liquidate(alice, M_DAI, address(wsteth), type(uint256).max, 0);
        }
        assertEq(pool.userCollateralOf(alice, C_WSTETH), 0);
        assertGt(pool.userDebtToken(alice, M_DAI), 0); // 留有坏账
        pool.handleBadDebt(alice, M_DAI);
        assertEq(pool.userDebtToken(alice, M_DAI), 0);
        // DAI 市场守恒（容差）；USDC 市场现金未受影响
        _assertMarketConservationApprox(M_DAI, 1e15);
        assertEq(_marketCash(M_USDC), usdcCashBefore);
    }

    function test_BadDebtInOneMarketDoesNotAffectOthers() public {
        _supply(bob, 200_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 200_000e18);
        _supplyMarket(address(usdt), M_USDT, bob, 200_000e6);
        // alice USDC 债务健康（ETH 抵押），DAI 坏账隔离
        _supplyCollateral(alice, 2 ether); // 6000
        _borrowMarket(M_USDC, alice, 1000e6, 1);
        uint256 usdcIndexBefore = _marketSupply(M_USDC);
        // 坏账 DAI：carol
        _supplyCollateralAsset(address(wsteth), carol, 0.1 ether);
        _borrowMarket(M_DAI, carol, 100e18, 1);
        oracle.setPrice(address(wsteth), 1e8);
        vm.warp(block.timestamp + 1000);
        _approveToken(address(dai), liquidator, type(uint256).max);
        uint256 guard = 0;
        while (pool.userCollateralOf(carol, C_WSTETH) > 0 && guard < 6) {
            vm.prank(liquidator);
            pool.liquidate(carol, M_DAI, address(wsteth), type(uint256).max, 0);
            guard++;
        }
        if (pool.userDebtToken(carol, M_DAI) > 0) {
            pool.handleBadDebt(carol, M_DAI);
        }
        assertGt(_marketSupply(M_USDC), 0);
        assertGt(pool.userDebtToken(alice, M_USDC), 0);
        assertApproxEqAbs(_marketBorrows(M_USDC), 1000e6, 1e6); // 含计息
        _assertMarketConservation(M_USDC);
        _assertMarketConservationApprox(M_DAI, 1e15);
        _assertMarketConservation(M_USDT);
    }

    // ==================== 双市场利率独立累计 ====================

    function test_BadDebtOneMarketKeepsGlobalTierForOtherDebt() public {
        // bob 提供两个市场现金；carol 以 wstETH 同 tier 借 USDC + DAI
        _supply(bob, 500_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 500_000e18);
        _supplyCollateralAsset(address(wsteth), carol, 1 ether); // 3000
        _borrowMarket(M_USDC, carol, 400e6, 3); // 总债务 1600 ≤ 2100
        _borrowMarket(M_DAI, carol, 1200e18, 3);
        assertEq(uint256(pool.userGlobalTier(carol)), 3);
        // wstETH 崩盘 → 一轮清算清走全部抵押
        oracle.setPrice(address(wsteth), 1e8);
        _approveToken(address(dai), liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(carol, M_DAI, address(wsteth), type(uint256).max, 0);
        assertEq(pool.userCollateralOf(carol, C_WSTETH), 0);
        assertGt(pool.userDebtToken(carol, M_DAI), 0); // DAI 留坏账
        assertGt(pool.userDebtToken(carol, M_USDC), 0); // USDC 债务仍在
        assertEq(uint256(pool.userGlobalTier(carol)), 3);
        assertTrue(pool.isLiquidatable(carol));

        // 只处理 DAI 坏账 → 全局 tier 必须保留（USDC 债务仍存在）
        pool.handleBadDebt(carol, M_DAI);
        assertEq(pool.userDebtToken(carol, M_DAI), 0);
        assertEq(uint256(pool.userGlobalTier(carol)), 3, "global tier must survive other-market debt");
        assertGt(pool.userDebtToken(carol, M_USDC), 0);
        assertTrue(pool.isLiquidatable(carol));

        // USDC 市场坏账处理后才清零
        pool.handleBadDebt(carol, M_USDC);
        assertEq(pool.userDebtToken(carol, M_USDC), 0);
        assertEq(uint256(pool.userGlobalTier(carol)), 0);
        _assertMarketConservationApprox(M_DAI, 1e15);
        _assertMarketConservation(M_USDC);
    }

    function test_IndependentAccrualPerMarket() public {
        _supply(bob, 100_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 100_000e18);
        _supplyCollateral(alice, 10 ether); // 30_000
        _borrowMarket(M_USDC, alice, 1000e6, 1); // USDC 利用率低
        // DAI 市场高利用率借款（carol 以 2 WBTC = 200_000 抵押，tier5 maxLTV 75%）
        _supplyCollateralAsset(address(wbtc), carol, 2e8); // 200_000 USD
        _borrowMarket(M_DAI, carol, 90_000e18, 5);
        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        uint256 usdcBorrowApr = pool.marketBorrowAPR(M_USDC, 1);
        uint256 daiBorrowApr = pool.marketBorrowAPR(M_DAI, 1);
        // DAI 市场利用率远高 → 利率更高
        assertGt(daiBorrowApr, usdcBorrowApr);
        _assertMarketConservation(M_USDC);
        _assertMarketConservation(M_DAI);
    }

    function test_CollectTreasuryPerMarket() public {
        // USDT + DAI 两个市场各自产生 Treasury
        _supplyMarket(address(usdt), M_USDT, bob, 200_000e6);
        _supplyMarket(address(dai), M_DAI, bob, 200_000e18);
        _supplyCollateral(alice, 10 ether); // 30_000
        _borrowMarket(M_USDT, alice, 3000e6, 5);
        _borrowMarket(M_DAI, alice, 3000e18, 5);
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        (,,,, uint256 tUsdt,) = pool.marketAccounts(M_USDT);
        (,,,, uint256 tDai,) = pool.marketAccounts(M_DAI);
        assertGt(tUsdt, 0);
        assertGt(tDai, 0);

        address treasuryAddr = makeAddr("treasury");
        vm.prank(admin);
        pool.setTreasuryAddress(treasuryAddr);
        uint256 usdtBefore = usdt.balanceOf(treasuryAddr);
        uint256 daiBefore = dai.balanceOf(treasuryAddr);

        vm.prank(alice);
        pool.collectTreasury(M_USDT);
        vm.prank(alice);
        pool.collectTreasury(M_DAI);

        (,,,, uint256 tUsdtAfter,) = pool.marketAccounts(M_USDT);
        (,,,, uint256 tDaiAfter,) = pool.marketAccounts(M_DAI);
        assertEq(tUsdtAfter, 0);
        assertEq(tDaiAfter, 0);
        assertEq(usdt.balanceOf(treasuryAddr) - usdtBefore, tUsdt);
        assertEq(dai.balanceOf(treasuryAddr) - daiBefore, tDai);
        _assertMarketConservationApprox(M_USDT, 1e6);
        _assertMarketConservationApprox(M_DAI, 1e15);
    }
}
