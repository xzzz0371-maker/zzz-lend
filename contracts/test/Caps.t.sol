// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";

/// @notice 供应/抵押上限风控测试：
///         - marketSupplyCap：市场总供应（token 单位）达上限后新存款被拒，提款/还款后释放空间；
///         - collateralCap：某抵押品池内总量达上限后新抵押被拒，提款/清算后释放空间；
///         - 0 = 无限制（默认，向后兼容）；仅 PARAM_ADMIN 可设置；非法 id 拒绝。
contract CapsTest is BaseSetupV2 {
    function _supplyCap(uint8 m) internal view returns (uint256) {
        return pool.marketSupplyCap(m);
    }

    // ==================== supply cap ====================

    function test_SupplyCapBlocksAtLimit() public {
        vm.prank(admin);
        pool.setMarketSupplyCap(M_USDC, 20_000e6); // 20_000 USDC 上限
        assertEq(_supplyCap(M_USDC), 20_000e6);

        _supply(alice, 10_000e6);
        _supply(bob, 10_000e6); // 正好到顶
        address carol = makeAddr("carol");
        usdc.transfer(carol, 100e6);
        vm.prank(carol);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(carol);
        vm.expectRevert(bytes("supply cap hit"));
        pool.supply(M_USDC, 100e6);
        _assertMarketConservation(M_USDC);
    }

    function test_SupplyCapRelaxedAfterWithdraw() public {
        vm.prank(admin);
        pool.setMarketSupplyCap(M_USDC, 20_000e6);
        _supply(alice, 10_000e6);
        _supply(bob, 10_000e6);

        // 提款释放空间后可再次存入
        vm.prank(bob);
        pool.withdraw(M_USDC, 5_000e6);
        address carol = makeAddr("carol");
        _fundAndSupply(carol, 5_000e6);
        assertTrue(pool.userSharesOf(carol, M_USDC) > 0);
        _assertMarketConservation(M_USDC);
    }

    function test_SupplyCapZeroMeansUnlimited() public {
        assertEq(_supplyCap(M_USDC), 0); // 默认无限制
        _supply(alice, 400_000e6);
        _supply(bob, 400_000e6);
        assertEq(pool.userSharesOf(bob, M_USDC), 400_000e6);
        _assertMarketConservation(M_USDC);
    }

    function test_SupplyCapOnlyParamAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.setMarketSupplyCap(M_USDC, 1e6);
        vm.prank(admin);
        pool.setMarketSupplyCap(M_USDC, 1e6);
        assertEq(_supplyCap(M_USDC), 1e6);
    }

    function test_SupplyCapBadMarketReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("bad market"));
        pool.setMarketSupplyCap(99, 1e6);
    }

    // ==================== collateral cap ====================

    function test_CollateralCapBlocksAcrossUsers() public {
        vm.prank(admin);
        pool.setCollateralCap(C_ETH, 2 ether); // 全池 ETH 抵押上限 2 ETH
        assertEq(pool.collateralCap(C_ETH), 2 ether);

        _supplyCollateral(alice, 1.5 ether);
        vm.prank(bob);
        vm.expectRevert(bytes("collateral cap hit"));
        pool.supplyCollateral{value: 0.6 ether}(); // 1.5+0.6 > 2
        // 恰好剩余空间可进
        vm.prank(bob);
        pool.supplyCollateral{value: 0.5 ether}();
        assertEq(pool.collateralTotal(C_ETH), 2 ether);
    }

    function test_CollateralCapReleasedByWithdraw() public {
        vm.prank(admin);
        pool.setCollateralCap(C_ETH, 2 ether);
        _supplyCollateral(alice, 1.5 ether);
        _supplyCollateral(bob, 0.5 ether);

        vm.prank(alice);
        pool.withdrawCollateral(ETH, 0.5 ether); // 释放 0.5
        vm.prank(makeAddr("carol"));
        pool.supplyCollateral{value: 0.4 ether}(); // 现在可进
        assertEq(pool.collateralTotal(C_ETH), 1.9 ether);
    }

    function test_CollateralCapReleasedByLiquidation() public {
        vm.prank(admin);
        pool.setCollateralCap(C_ETH, 1 ether);
        _supplyCollateral(alice, 1 ether); // 抵押满
        _supply(bob, 500_000e6);
        _borrow(alice, 2400e6, 5);
        oracle.setPrice(ETH, 1000e8); // 抵押 1000 → 可清算
        assertTrue(pool.isLiquidatable(alice));
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, M_USDC, ETH, 1000e6, 0);
        assertLt(pool.collateralTotal(C_ETH), 1 ether, "liquidation must release collateral cap");
        uint256 freed = 1 ether - pool.collateralTotal(C_ETH);
        // 释放后可再次供 ≤ freed
        vm.deal(bob, 1 ether);
        vm.prank(bob);
        pool.supplyCollateral{value: freed}();
        assertEq(pool.collateralTotal(C_ETH), 1 ether);
        // 再供一点 → 顶格 revert
        vm.prank(makeAddr("carol"));
        vm.expectRevert(bytes("collateral cap hit"));
        pool.supplyCollateral{value: 0.01 ether}();
    }

    function test_CollateralCapOnlyParamAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.setCollateralCap(C_ETH, 1e18);
        vm.prank(admin);
        pool.setCollateralCap(C_ETH, 1e18);
        assertEq(pool.collateralCap(C_ETH), 1e18);
    }

    function test_CollateralCapBadIdReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("bad collateral"));
        pool.setCollateralCap(99, 1e18);
    }

    function _fundAndSupply(address who, uint256 amount) internal {
        usdc.transfer(who, amount);
        vm.prank(who);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(who);
        pool.supply(M_USDC, amount);
    }
}
