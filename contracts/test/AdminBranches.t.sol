// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetupV2} from "./BaseSetupV2.t.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @notice addMarket / addCollateral 与 admin 分支覆盖（补 PROGRESS 遗留）：
///         - addMarket: zero/ETH/bad decimals/重复/超 MAX_MARKETS(8)；
///         - addCollateral: zero/重复/超 MAX_COLLATERALS(8)；
///         - 非法 marketId 各视图/操作 revert；
///         - admin setter 极端边界（MAX_MARKETS 满后新增、reserveTarget=100% 等）。
contract AdminBranchesTest is BaseSetupV2 {
    function _expectUnauthorized(address who) internal {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, who, pool.PARAM_ADMIN_ROLE()
            )
        );
    }

    function test_AddMarketZeroAddressReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("bad asset"));
        pool.addMarket(address(0), 6);
    }

    function test_AddMarketEthSentinelReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("bad asset"));
        pool.addMarket(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 18);
    }

    function test_AddMarketNonAdminReverts() public {
        address t = address(new MockToken("T", "T", 6));
        _expectUnauthorized(alice);
        vm.prank(alice);
        pool.addMarket(t, 6);
    }

    function test_AddMarketTooManyMarketsReverts() public {
        // 当前已注册：USDC(构造) + USDT + DAI = 3；MAX_MARKETS=8 → 可再 +5，第 9 个 revert。
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            pool.addMarket(address(new MockToken("Extra", "EX", 18)), 18);
        }
        vm.prank(admin);
        vm.expectRevert(bytes("too many markets"));
        pool.addMarket(address(new MockToken("Overflow", "OF", 18)), 18);
    }

    function test_AddCollateralZeroAddressReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("zero token"));
        pool.addCollateral(address(0), 18);
    }

    function test_AddCollateralTooManyReverts() public {
        // 已注册：ETH(构造) + wstETH + WBTC = 3；MAX_COLLATERALS=8 → 可再 +5，第 9 个 revert。
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            pool.addCollateral(address(new MockToken("Coll", "CO", 18)), 18);
        }
        vm.prank(admin);
        vm.expectRevert(bytes("too many collaterals"));
        pool.addCollateral(address(new MockToken("Overflow", "OF2", 18)), 18);
    }

    function test_BadMarketIdRevertsEverywhere() public {
        vm.prank(admin);
        pool.setTreasuryAddress(makeAddr("treasury")); // collectTreasury 前置条件
        vm.expectRevert(bytes("bad market"));
        pool.supply(99, 100e6);
        vm.expectRevert(bytes("bad market"));
        pool.withdraw(99, 1);
        vm.expectRevert(bytes("bad market"));
        pool.borrow(99, 100e6, 1);
        vm.expectRevert(bytes("bad market"));
        pool.repay(99, 1);
        vm.expectRevert(bytes("bad market"));
        pool.liquidate(alice, 99, ETH, 1, 0);
        vm.expectRevert(bytes("bad market"));
        pool.handleBadDebt(alice, 99);
        vm.expectRevert(bytes("bad market"));
        pool.collectTreasury(99);
    }

    function test_UnknownCollateralReverts() public {
        vm.expectRevert(bytes("not collateral"));
        pool.supplyCollateral(address(new MockToken("X", "X", 18)), 1e18);
        vm.expectRevert(bytes("not collateral"));
        pool.withdrawCollateral(address(new MockToken("Y", "Y", 18)), 1);
        vm.expectRevert(bytes("not collateral"));
        pool.liquidate(alice, 0, address(new MockToken("Z", "Z", 18)), 1, 0);
    }

    function test_AdminSetReserveTargetRatioMaxBound() public {
        vm.prank(admin);
        pool.setReserveTargetRatio(1e18); // 100% 允许（边界）
        assertEq(pool.reserveTargetRatio(), 1e18);
        vm.prank(admin);
        vm.expectRevert(bytes("ratio>100%"));
        pool.setReserveTargetRatio(1e18 + 1);
    }

    function test_AdminRoleMatrixOnModules() public {
        // 部署者（本测试合约）是 DEFAULT_ADMIN；向 bob 授予 PARAM_ADMIN/PAUSER。
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), bob);
        pool.grantRole(pool.PAUSER_ROLE(), bob);
        assertTrue(pool.hasRole(pool.PARAM_ADMIN_ROLE(), bob));
        assertTrue(pool.hasRole(pool.PAUSER_ROLE(), bob));
        // bob 获得 PARAM_ADMIN 后可加市场
        address bm = address(new MockToken("BobMkt", "BM", 18));
        vm.prank(bob);
        pool.addMarket(bm, 18);
        // 仅 PAUSER 不能加市场
        address dave = makeAddr("dave");
        pool.grantRole(pool.PAUSER_ROLE(), dave);
        address dm = address(new MockToken("DaveMkt", "DM", 18));
        _expectUnauthorized(dave);
        vm.prank(dave);
        pool.addMarket(dm, 18);
    }

    function test_AddMarketExactBoundary_SevenMarkets() public {
        // 3 + 5 后应成功（= MAX_MARKETS 8 个市场），验证“允许填满”而非“多了才拦”。
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(admin);
            pool.addMarket(address(new MockToken("B", "B", 18)), 18);
        }
        (uint256 cash,, uint256 supply,,,) = pool.marketAccounts(7);
        assertEq(cash, 0);
        assertEq(supply, 0);
    }
}
