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
        // base 2% + slope1 8% * 0.5 = 6% APR for tier 1
        uint256 apr = irm.getBorrowAPR(5e17, 1);
        assertApproxEqAbs(apr, 6e16, 1e15);
    }

    function test_NormalZeroUtilizationBorrowAPR() public view {
        // NORMAL 预设 utilization=0 时 Borrow APR = baseRate = 2%
        uint256 apr = irm.getBorrowAPR(0, 1);
        assertApproxEqAbs(apr, 2e16, 1e15);
    }

    function test_AboveKinkRateJumps() public view {
        uint256 belowKink = irm.getBorrowAPR(79e16, 1);
        uint256 aboveKink = irm.getBorrowAPR(81e16, 1);
        assertGt(aboveKink, belowKink);
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
