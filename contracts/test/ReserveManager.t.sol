// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract ReserveManagerTest is BaseSetup {
    function _setupBorrow() internal {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether); // 6000
        _borrow(alice, 3000e6, 5);
    }

    function test_ReserveAccruesFactorShare() public {
        _setupBorrow();
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        uint256 reserve = pool.totalReserve();
        assertGt(reserve, 0);
        // reserve = 5% of total interest（固定费率）
        uint256 interest = pool.getTotalBorrows() - 3000e6;
        assertApproxEqAbs(reserve, interest * 5e16 / 1e18, 1e6);
    }

    function test_SkimMovesFundsToReserveManager() public {
        _setupBorrow();
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        uint256 reserve = pool.totalReserve();
        pool.skimReserve();
        assertEq(pool.totalReserve(), 0);
        assertApproxEqAbs(reserveManager.balance(), reserve, 1e6);
    }

    function test_SkimWhenNoReserveReverts() public {
        vm.expectRevert(bytes("no reserve"));
        pool.skimReserve();
    }

    function test_CoverBadDebtOnlyByLendingPool() public {
        _setupBorrow();
        vm.warp(block.timestamp + 365 days);
        pool.accrue();
        pool.skimReserve();
        vm.prank(alice);
        vm.expectRevert(bytes("not pool"));
        reserveManager.coverBadDebt(1e6);
    }

    function test_SetLendingPoolOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        reserveManager.setLendingPool(alice);
    }

    function test_SetLendingPoolZeroAddressReverts() public {
        vm.expectRevert(bytes("zero address"));
        reserveManager.setLendingPool(address(0));
    }

    function test_ReserveManagerHasNoArbitraryWithdraw() public {
        // No function exposes user/reserve funds to arbitrary recipients.
        // Only coverBadDebt (to the pool) and setLendingPool (owner) exist.
        assertEq(reserveManager.balance(), 0);
    }
}
