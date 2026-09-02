// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";

contract InterestRateModelTest is Test {
    InterestRateModel internal irm;

    function setUp() public {
        irm = new InterestRateModel();
    }

    function test_RateIncreasesWithUtilization() public view {
        uint256 r0 = irm.getBorrowRatePerSecond(0, 1);
        uint256 r50 = irm.getBorrowRatePerSecond(5e17, 1);
        uint256 r100 = irm.getBorrowRatePerSecond(1e18, 1);
        assertGt(r50, r0);
        assertGt(r100, r50);
    }

    function test_HigherTierHigherRate() public view {
        uint256 r1 = irm.getBorrowRatePerSecond(5e17, 1);
        uint256 r5 = irm.getBorrowRatePerSecond(5e17, 5);
        assertGt(r5, r1);
    }

    function test_AnnualizedRateAtHalfUtilization() public view {
        // base 0.5% + slope1 4% * 0.5 = 2.5% APR for tier 1
        uint256 apr = irm.getBorrowAPR(5e17, 1);
        assertApproxEqAbs(apr, 2.5e16, 1e15);
    }

    function test_NormalZeroUtilizationBorrowAPR() public view {
        // NORMAL 预设 utilization=0 时 Borrow APR = baseRate = 0.5%
        uint256 apr = irm.getBorrowAPR(0, 1);
        assertApproxEqAbs(apr, 5e15, 1e15);
    }

    function test_AboveKinkRateJumps() public view {
        uint256 belowKink = irm.getBorrowAPR(79e16, 1);
        uint256 aboveKink = irm.getBorrowAPR(81e16, 1);
        assertGt(aboveKink, belowKink);
    }

    /// @notice NORMAL 三段式：80/85/85.01/90/100 的边界值与连续性（tier1，无溢价）。
    function test_ThreeSegmentCurveNormal() public view {
        // 0.5% + 4%*0.8 = 3.7%
        assertApproxEqAbs(irm.getBorrowAPR(8e17, 1), 3.7e16, 1e10);
        // 3.7% + 25%*0.05 = 4.95%（kink2 上边界，属中段）
        assertApproxEqAbs(irm.getBorrowAPR(85e16, 1), 4.95e16, 1e10);
        // 85.01% → 中段之后：4.95% + 50%*0.0001 = 4.955%（末段起点连续性）
        uint256 justAbove = irm.getBorrowAPR(8501e14, 1);
        assertApproxEqAbs(justAbove, 4.955e16, 1e10);
        // 4.95% + 50%*0.05 = 7.45%
        assertApproxEqAbs(irm.getBorrowAPR(9e17, 1), 7.45e16, 1e10);
        // 4.95% + 50%*0.15 = 12.45%
        assertApproxEqAbs(irm.getBorrowAPR(1e18, 1), 12.45e16, 1e10);
        // 单调性：80 → 85 → 85.01 → 90 → 100
        assertGe(irm.getBorrowAPR(85e16, 1), irm.getBorrowAPR(8e17, 1));
        assertGe(justAbove, irm.getBorrowAPR(85e16, 1));
        assertGe(irm.getBorrowAPR(9e17, 1), justAbove);
        assertGe(irm.getBorrowAPR(1e18, 1), irm.getBorrowAPR(9e17, 1));
        // 段斜率不同：80→85 增 1.25%，85→90 增 2.5%（末段更陡）
        uint256 seg2 = irm.getBorrowAPR(85e16, 1) - irm.getBorrowAPR(8e17, 1);
        uint256 seg3 = irm.getBorrowAPR(9e17, 1) - irm.getBorrowAPR(85e16, 1);
        assertApproxEqAbs(seg2, 1.25e16, 1e10);
        assertApproxEqAbs(seg3, 2.5e16, 1e10);
    }

    function test_SetSlope2aAndKink2OnlyOwner() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        irm.setSlope2a(3e17);
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        irm.setKink2(9e17);
        // owner 可配，kink2 不能低于 kink1
        irm.setSlope2a(3e17); // 中段斜率 30%
        irm.setKink2(9e17); // kink2 = 90%
        // util 95%：0.5% + 4%*0.8 + 30%*0.1 + 50%*0.05 = 9.2%
        assertApproxEqAbs(irm.getBorrowAPR(95e16, 1), 9.2e16, 1e14);
        vm.expectRevert(bytes("kink2 out of range"));
        irm.setKink2(7e17);
    }

    function test_SetParamsOnlyOwner() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        irm.setParams(0, 0, 0, 8e17);
    }

    function test_KinkMustBeAtMostWad() public {
        vm.expectRevert(bytes("kink>WAD"));
        irm.setParams(0, 0, 0, 1e18 + 1);
    }

    function test_SetTierPremiumOnlyOwner() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        irm.setTierPremium(5, 1e17);
    }

    function test_SetTierPremiumSuccess() public {
        irm.setTierPremium(5, 8e16);
        assertApproxEqAbs(irm.getBorrowAPR(5e17, 5) - irm.getBorrowAPR(5e17, 1), 8e16, 1e14);
        vm.expectRevert(bytes("bad tier"));
        irm.setTierPremium(6, 1e17);
    }
}
