// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

/// @notice 清算时间差测试：第一次清算后 warp 一段时间，价格继续下跌，再第二次清算。
/// 覆盖：1h/6h/24h × 价格续跌 5%/10%/20%。
contract LiquidationTimeGapTest is BaseSetup {
    uint256[] internal gaps = [1 hours, 6 hours, 24 hours];
    uint256[] internal drops = [5, 10, 20];

    function test_TimeGapSecondLiquidation() public {
        _supply(bob, 200_000e6);
        _approveUsdc(liquidator, type(uint256).max);

        for (uint256 g = 0; g < gaps.length; g++) {
            for (uint256 d = 0; d < drops.length; d++) {
                address borrower =
                    makeAddr(string(abi.encodePacked("gapBorrower", vm.toString(g), "-", vm.toString(d))));
                oracle.setPrice(ETH, 3000e8); // 重置价格，保证 LTV 校验
                vm.deal(borrower, 1 ether);
                vm.prank(borrower);
                pool.supplyCollateral{value: 1 ether}();
                vm.prank(borrower);
                pool.borrow(2400e6, 5); // 80% LTV, HF=1.11

                // 第一次：ETH 从 3000 跌到 1800 (-40%) → HF=0.675 可清算
                oracle.setPrice(ETH, 1800e8);
                vm.prank(liquidator);
                pool.liquidate(borrower, 2400e6, 0); // cover 50% = 1200
                uint256 debtAfterFirst = pool.getDebt(borrower);
                assertLt(debtAfterFirst, 2400e6 * 1e12);
                assertLt(pool.getUserHealthFactor(borrower), 1e18); // 仍可清算

                // 时间差：利息累计
                vm.warp(block.timestamp + gaps[g]);
                vm.roll(block.number + 1);
                pool.accrue();
                uint256 debtBeforeSecond = pool.getDebt(borrower);
                assertGt(debtBeforeSecond, debtAfterFirst); // 时间差内利息累计正确

                // 价格继续下跌 drop%
                uint256 newPrice = 1800e8 * (100 - drops[d]) / 100;
                oracle.setPrice(ETH, newPrice);

                // 第二次清算
                vm.prank(liquidator);
                pool.liquidate(borrower, 100_000e6, 0);
                (, uint256 collAfter,,,,,) = pool.getUserPosition(borrower);
                uint256 debtAfterSecond = pool.getDebt(borrower);
                // 坏账可能扩大：要么恢复健康（HF>=1），要么抵押耗尽残留债务
                if (collAfter == 0) {
                    assertGt(debtAfterSecond, 0); // 坏账残留
                } else {
                    assertGe(pool.getUserHealthFactor(borrower), 1e18);
                }
                // 资金守恒
                _assertInvariant();
            }
        }
    }

    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued() + pool.boostPool();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e7 : (rhs - lhs) <= 1e7, "invariant broken");
    }
}
