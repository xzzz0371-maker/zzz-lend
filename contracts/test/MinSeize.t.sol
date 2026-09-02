// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract MinSeizeTest is BaseSetup {
    function _setupLiquidatable() internal {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8); // HF = 0.9
        _approveUsdc(liquidator, type(uint256).max);
    }

    function test_MinSeizePasses() public {
        _setupLiquidatable();
        (, uint256 collBefore,,,,,) = pool.getUserPosition(alice);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0.5 ether); // 实际约 0.525 ETH >= 0.5
        (, uint256 collAfter,,,,,) = pool.getUserPosition(alice);
        assertLt(collAfter, collBefore);
    }

    function test_MinSeizeRevertsWhenTooHigh() public {
        _setupLiquidatable();
        vm.prank(liquidator);
        vm.expectRevert(bytes("seize below min"));
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0.6 ether); // 实际约 0.525 < 0.6
    }

    function test_MinSeizeZeroNoLimit() public {
        _setupLiquidatable();
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0);
        assertLt(pool.getDebt(alice), 2000e6 * 1e12);
    }
}
