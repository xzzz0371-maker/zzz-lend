// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";

contract UsdcPegTest is BaseSetup {
    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }

    function test_UsdcAtOneDollarSameAsBefore() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether); // 3000 USD
        uint256 maxB = pool.maxBorrowable(alice, 1);
        _borrow(alice, 1500e6, 1); // 50% LTV
        // HF = 3000*0.6/1500 = 1.2
        assertApproxEqAbs(pool.getUserHealthFactor(alice), 12e17, 1e12);
        // maxBorrowable 与理论一致：capacity-debt 全按 1:1
        assertApproxEqAbs(maxB, 1500e6, 1e6);
        _assertInvariant();
    }

    function test_UsdcPremiumRaisesLtvAndLowersHf() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1500e6, 1);
        uint256 hfAtOne = pool.getUserHealthFactor(alice); // 1.2

        oracle.setPrice(address(usdc), 11e7); // USDC = 1.1 USD 溢价
        uint256 hfPremium = pool.getUserHealthFactor(alice);
        // 债务美元价值上升 → HF 下降
        assertLt(hfPremium, hfAtOne);
        // 债务 = 1500*1.1 = 1650 → HF = 3000*0.6/1650 = 1.0909
        uint256 expPremium = uint256(3000e18) * uint256(6e17) / uint256(1650e18);
        assertApproxEqAbs(hfPremium, expPremium, 1e12);
        // maxBorrowable：已借 1500 USDC（按 1.1 计价 = 1650 USD）已超过 tier1 能力 1500 USD → 0
        assertEq(pool.maxBorrowable(alice, 1), 0);
        _assertInvariant();
    }

    function test_UsdcDepegLowersLtvAndRaisesHf() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1500e6, 1);
        uint256 hfAtOne = pool.getUserHealthFactor(alice);

        oracle.setPrice(address(usdc), 9e7); // USDC = 0.9 USD 脱锚
        uint256 hfDepeg = pool.getUserHealthFactor(alice);
        assertGt(hfDepeg, hfAtOne);
        // 债务 = 1500*0.9 = 1350 → HF = 3000*0.6/1350 = 1.333
        uint256 expDepeg = uint256(3000e18) * uint256(6e17) / uint256(1350e18);
        assertApproxEqAbs(hfDepeg, expDepeg, 1e12);
        _assertInvariant();
    }

    function test_UsdcPremiumCanTriggerLiquidation() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5); // LTV 66.7%, HF=1.35 @1.0
        assertGt(pool.getUserHealthFactor(alice), 1e18);

        oracle.setPrice(address(usdc), 15e7); // USDC = 1.5 USD
        // 债务 = 3000 USD → HF = 3000*0.9/3000 = 0.9 < 1
        assertTrue(pool.isLiquidatable(alice));

        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 1000e6, 0);
        uint256 debtCap = uint256(2000e6) * uint256(15e7) * uint256(1e12) / uint256(1e8);
        assertLt(pool.getDebt(alice), debtCap);
        _assertInvariant();
    }

    function test_UsdcPriceZeroReverts() public {
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 500e6, 1);
        oracle.setPrice(address(usdc), 0);
        vm.expectRevert(bytes("bad usdc price"));
        pool.getUserHealthFactor(alice);
    }
}
