// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {BaseSetup} from "./BaseSetup.t.sol";

contract PermissionsTest is BaseSetup {
    function test_OnlyParamAdminCanSetFixedFeeParams() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setReserveTargetRatio(3e16);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setReserveFactor(5e16);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setTreasuryFactor(3e16);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setTreasuryAddress(makeAddr("treasury"));

        vm.prank(admin);
        pool.setReserveTargetRatio(2e16);
        vm.prank(admin);
        pool.setReserveFactor(6e16);
        vm.prank(admin);
        pool.setTreasuryFactor(4e16);
        vm.prank(admin);
        pool.setTreasuryAddress(makeAddr("treasury"));
        assertEq(pool.reserveTargetRatio(), 2e16);
        assertEq(pool.reserveFactor(), 6e16);
        assertEq(pool.treasuryFactor(), 4e16);
        assertEq(pool.treasuryAddress(), makeAddr("treasury"));
    }

    function test_OnlyParamAdminCanSwapModels() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setInterestRateModel(irm);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setRiskManager(riskManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setPriceOracle(oracle);
        // 覆盖剩余模块 setter：LiquidationManager / ReserveManager
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setLiquidationManager(liquidationManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setReserveManager(reserveManager);
        vm.prank(admin);
        pool.setLiquidationManager(liquidationManager);
        vm.prank(admin);
        pool.setReserveManager(reserveManager);
        assertEq(address(pool.liquidationManager()), address(liquidationManager));
        assertEq(address(pool.reserveManager()), address(reserveManager));
    }

    function test_OnlyPauserCanPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PAUSER_ROLE())
        );
        vm.prank(alice);
        pool.pause();
        vm.prank(admin);
        pool.pause();
        assertTrue(pool.paused());
    }

    function test_PausedBlocksSupplyButAllowsWithdrawAndRepay() public {
        _supply(alice, 10_000e6);
        _supplyCollateral(bob, 1 ether);
        _borrow(bob, 1000e6, 5);
        vm.prank(admin);
        pool.pause();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        pool.supply(100e6);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(bob);
        pool.supplyCollateral{value: 1 ether}();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(bob);
        pool.borrow(100e6, 5);

        // withdraw still allowed during pause
        vm.prank(alice);
        pool.withdraw(1000e6);

        // repay still allowed during pause
        _approveUsdc(bob, type(uint256).max);
        vm.prank(bob);
        pool.repay(type(uint256).max);

        vm.prank(admin);
        pool.unpause();
        assertFalse(pool.paused());
    }

    function test_AdminCannotDrainUserSupply() public {
        _supply(alice, 10_000e6);
        vm.expectRevert(bytes("insufficient shares"));
        vm.prank(admin);
        pool.withdraw(10_000e6);
    }

    function test_AdminCannotMoveUserCollateral() public {
        _supplyCollateral(alice, 1 ether);
        vm.expectRevert(bytes("insufficient collateral"));
        vm.prank(admin);
        pool.withdrawCollateral(1 ether);
    }

    function test_AdminCannotRepayForUser() public {
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 5);
        vm.expectRevert(bytes("no debt"));
        vm.prank(admin);
        pool.repay(100e6);
    }

    function test_NoFunctionTransfersUserShares() public {
        _supply(alice, 10_000e6);
        (uint256 shares,,,,,,) = pool.getUserPosition(alice);
        assertEq(shares, 10_000e6);
        // shares are non-transferable: only the owner can withdraw them
        vm.expectRevert(bytes("insufficient shares"));
        vm.prank(bob);
        pool.withdraw(shares);
    }
}
