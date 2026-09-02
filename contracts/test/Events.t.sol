// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {BaseSetup} from "./BaseSetup.t.sol";
import {SwitchableOracle} from "../src/oracle/SwitchableOracle.sol";

/// @notice 关键会计事件（核心路径）覆盖测试 + 用户操作以状态断言验证。
contract EventsTest is BaseSetup {
    event InterestAccrued(uint256 interest, uint256 intervalSeconds);
    event OracleSwitched(bool useSettablePrice);

    function test_SupplyWithdrawState() public {
        _supply(alice, 1000e6);
        (uint256 shares,,,,,,) = pool.getUserPosition(alice);
        assertEq(shares, 1000e6);
        vm.prank(alice);
        pool.withdraw(0, shares);
        (uint256 sharesAfter,,,,,,) = pool.getUserPosition(alice);
        assertEq(sharesAfter, 0);
        assertEq(usdc.balanceOf(alice), 500_000e6);
    }

    function test_BorrowRepayState() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        vm.prank(alice);
        pool.borrow(0, 1500e6, 1);
        (,, uint256 debt,,,,) = pool.getUserPosition(alice);
        assertEq(debt, 1500e18); // WAD
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(0, 200e6);
        assertEq(pool.getDebt(alice), 1300e18);
    }

    function test_LiquidateState() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        vm.prank(alice);
        pool.borrow(0, 2000e6, 5);
        oracle.setPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 2000e8); // HF=0.9
        (, uint256 collBefore, uint256 debtBefore,,,,) = pool.getUserPosition(alice);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0);
        (, uint256 collAfter, uint256 debtAfter,,,,) = pool.getUserPosition(alice);
        assertLt(debtAfter, debtBefore);
        assertLt(collAfter, collBefore);
    }

    function test_InterestAccruedEvent() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        vm.prank(alice);
        pool.borrow(0, 2000e6, 5);
        vm.warp(block.timestamp + 30 days);
        uint256 dt = 30 days;
        uint256 rate = irm.getBorrowRatePerSecond(pool.getUtilization(), 5);
        uint256 expectedInterest = pool.getTotalBorrows() * rate * dt / 1e18;
        vm.expectEmit(true, true, true, true);
        emit InterestAccrued(expectedInterest, dt);
        pool.accrue();
    }

    function test_BadDebtRealizedEvent() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        vm.prank(alice);
        pool.borrow(0, 2400e6, 5);
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        if (pool.totalReserve() > 0) pool.skimReserve();
        oracle.setPrice(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 10_000e6, 0);

        vm.recordLogs();
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("BadDebtRealized(address,uint256,uint256,uint256,uint256,uint256)")) {
                found = true;
            }
        }
        assertTrue(found, "BadDebtRealized not emitted");
    }

    function test_OracleSwitchedEvent() public {
        SwitchableOracle so = new SwitchableOracle(oracle);
        so.grantRole(so.PAUSER_ROLE(), admin);
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit OracleSwitched(true);
        so.enableSettable();
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit OracleSwitched(false);
        so.disableSettable();
    }
}
