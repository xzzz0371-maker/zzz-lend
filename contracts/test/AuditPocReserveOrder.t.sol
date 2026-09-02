// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";
import {console2} from "forge-std/console2.sol";

/// @notice 审计 PoC：记录 handleBadDebt 的损失吸收顺序（depositors vs book reserve）。
/// 目的：验证“账面风险储备是否先于存款人吸收坏账”。当前实现为：
///   物理储备(reserveManager) → 存款人(supplyIndex) → 账面 reserve → treasury。
/// 与“储备=第一损失缓冲”的产品意图不一致（设计发现 D1）。
contract AuditPocReserveOrder is BaseSetupV2 {
    function _usdcSupplyIndex() internal view returns (uint256) {
        (,,,,, uint256 x) = pool.marketAccounts(M_USDC);
        return x;
    }

    function _usdcBookReserve() internal view returns (uint256) {
        (,,, uint256 r,,) = pool.marketAccounts(M_USDC);
        return r;
    }

    function test_RecordBadDebtAbsorptionOrder() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        _borrow(alice, 2400e6, 5);
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        uint256 bookReserveBefore = _usdcBookReserve();
        uint256 supplyIndexBefore = _usdcSupplyIndex();
        console2.log("bookReserveBefore(raw):", bookReserveBefore);
        console2.log("supplyIndexBefore:", supplyIndexBefore);

        oracle.setPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        uint256 guard = 0;
        while (pool.userCollateralOf(alice, 0) > 0 && guard < 8) {
            vm.prank(liquidator);
            pool.liquidate(alice, M_USDC, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, type(uint256).max, 0);
            guard++;
        }
        uint256 badDebt = pool.userDebtToken(alice, M_USDC);
        uint256 bookReserveMid = _usdcBookReserve();
        console2.log("residual debt(raw):", badDebt);
        console2.log("bookReserve before handleBadDebt:", bookReserveMid);

        pool.handleBadDebt(alice, M_USDC);
        uint256 supplyIndexAfter = _usdcSupplyIndex();
        uint256 bookReserveAfter = _usdcBookReserve();
        console2.log("supplyIndexAfter:", supplyIndexAfter);
        console2.log("bookReserveAfter:", bookReserveAfter);
        console2.log(
            "SUPPLYINDEX_DECREASED=", (supplyIndexAfter < supplyIndexBefore) ? "true" : "false",
            " RESERVE_DEPLETED=", (bookReserveAfter < bookReserveMid) ? "true" : "false"
        );
        _assertMarketConservationApprox(M_USDC, 1e15);
    }

    /// @notice 记录 dust 减免：repay 使剩余 norm ≤ DUST(100) 时剩余债务被清零（供应商承担小额损失）。
    function test_RecordDustWriteoff() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 100e6, 1);
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(M_USDC, 99_999_899); // 留 101 raw（> DUST 100）
        uint256 leftover = pool.userDebtToken(alice, M_USDC);
        console2.log("leftover after repay-to-dust-edge:", leftover);
        vm.prank(alice);
        pool.repay(M_USDC, 1); // 触发 DUST 清零（余下 100 raw 被豁免）
        console2.log("debt after dust-trigger:", pool.userDebtToken(alice, M_USDC));
    }
}
