// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Vm} from "forge-std/Vm.sol";
import {BaseSetup} from "./BaseSetup.t.sol";
import {SwitchableOracle} from "../src/oracle/SwitchableOracle.sol";

/// @notice 事件覆盖测试：验证所有关键状态变更事件正确触发且参数完整。
contract EventsTest is BaseSetup {
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event Borrowed(address indexed user, uint256 tier, uint256 amount, uint256 newLtv, uint256 healthFactor);
    event Repaid(address indexed user, uint256 amount, uint256 remainingDebt);
    event Liquidated(
        address indexed liquidator,
        address indexed target,
        uint256 debtCovered,
        uint256 collateralSeized,
        uint256 postHealthFactor
    );
    event InterestAccrued(uint256 interest, uint256 intervalSeconds);
    event OracleSwitched(bool useSettablePrice);

    function test_SupplyWithdrawEvents() public {
        _supply(alice, 1000e6);
        (uint256 shares,,,,,,) = pool.getUserPosition(alice);
        vm.expectEmit(true, true, true, true);
        emit Withdrawn(alice, shares, shares); // 无计息时 amount==shares
        vm.prank(alice);
        pool.withdraw(shares);
    }

    function test_BorrowRepayEvents() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        // newLtv = 1500/3000 = 50%; hf = 3000*0.6/1500 = 1.2
        vm.expectEmit(true, true, true, true);
        emit Borrowed(alice, 1, 1500e6, 5e17, 12e17);
        _borrow(alice, 1500e6, 1);

        _approveUsdc(alice, type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Repaid(alice, 200e6, 1300e6 * 1e12);
        vm.prank(alice);
        pool.repay(200e6);
    }

    function test_LiquidateEvent() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8); // HF=0.9
        // 清算 1000e6：cover=1000e6, seize=0.525 ETH, 剩余 debt=1000e18(WAD), 抵押值=0.475*2000=950e18
        // postHF = 950e18 * 0.9 / 1000e18 = 0.855e18
        _approveUsdc(liquidator, type(uint256).max);
        vm.expectEmit(true, true, true, true);
        emit Liquidated(liquidator, alice, 1000e6, 0.525 ether, 855e15);
        vm.prank(liquidator);
        pool.liquidate(alice, 1000e6, 0);
    }

    function test_InterestAccruedEvent() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
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
        _borrow(alice, 2400e6, 5);
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        if (pool.totalReserve() > 0) pool.skimReserve();
        oracle.setPrice(ETH, 1e8);
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 10_000e6, 0);

        vm.recordLogs();
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice);
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
