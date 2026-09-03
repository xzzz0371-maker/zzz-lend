// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {RiskManager} from "../src/RiskManager.sol";

contract RiskManagerTest is Test {
    RiskManager internal rm;

    function setUp() public {
        rm = new RiskManager();
    }

    function test_DefaultTiers() public view {
        assertEq(rm.getMaxLTV(1), 5e17);
        assertEq(rm.getMaxLTV(2), 6e17);
        assertEq(rm.getMaxLTV(3), 7e17);
        assertEq(rm.getMaxLTV(4), 75e16);
        assertEq(rm.getMaxLTV(5), 8e17);
        assertEq(rm.getLiquidationThreshold(4), 85e16);
        assertEq(rm.getLiquidationThreshold(5), 9e17);
    }

    /// @notice 部署脚本主网前置项回归：ETH 哨兵地址 5 档 LTV/LT 必须非 0 且 LT>LTV
    ///         （若 RiskManager 构造默认被误改/漏配，此测试会先红）。
    function test_EthSentinelTiersNonZero_AfterDeployDefaults() public view {
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        uint256[5] memory expectLtv = [uint256(5e17), 6e17, 7e17, 75e16, 8e17];
        uint256[5] memory expectLt = [uint256(6e17), 7e17, 78e16, 85e16, 9e17];
        for (uint256 t = 1; t <= 5; t++) {
            uint256 ltv = rm.getMaxLTV(eth, t);
            uint256 lt = rm.getLiquidationThreshold(eth, t);
            assertGt(ltv, 0, "ETH LTV must not be 0");
            assertGt(lt, ltv, "ETH LT must exceed LTV");
            assertEq(ltv, expectLtv[t - 1]);
            assertEq(lt, expectLt[t - 1]);
        }
    }

    function test_ValidateBorrow() public {
        rm.validateBorrow(1, 100e18, 50e18);
        vm.expectRevert(bytes("ltv too high"));
        rm.validateBorrow(1, 100e18, 60e18);
        vm.expectRevert(bytes("no collateral"));
        rm.validateBorrow(1, 0, 10e18);
    }

    function test_HealthFactor() public view {
        // collateral 100k, LT 85% (tier4), debt 75k => ~1.133
        uint256 hf = rm.getHealthFactor(4, 100_000e18, 75_000e18);
        assertApproxEqAbs(hf, 1133333333333333333, 1e12);
        assertEq(rm.getHealthFactor(1, 100e18, 0), type(uint256).max);
        assertEq(rm.getHealthFactor(1, 0, 100e18), 0);
    }

    function test_OnlyOwnerCanSetParams() public {
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        rm.setTier(1, 5e17, 6e17);
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        rm.setLiquidationBonus(5e16);
        vm.prank(makeAddr("attacker"));
        vm.expectRevert();
        rm.setCloseFactor(5e17);
    }

    function test_TierValidation() public {
        vm.expectRevert(bytes("LT<=maxLTV"));
        rm.setTier(1, 5e17, 5e17);
        vm.expectRevert(bytes("maxLTV>90%"));
        rm.setTier(1, 95e16, 96e16);
        vm.expectRevert(bytes("bad tier"));
        rm.setTier(6, 5e17, 6e17);
    }

    function test_OwnerCanSetTier() public {
        rm.setTier(1, 5e17, 6e17);
        assertEq(rm.getMaxLTV(1), 5e17);
    }

    function test_OwnerSetsLiquidationBonus() public {
        rm.setLiquidationBonus(1e17);
        assertEq(rm.liquidationBonus(), 1e17);
        vm.expectRevert(bytes("bonus>20%"));
        rm.setLiquidationBonus(3e17);
    }

    function test_OwnerSetsCloseFactor() public {
        rm.setCloseFactor(4e17);
        assertEq(rm.closeFactor(), 4e17);
        vm.expectRevert(bytes("factor>100%"));
        rm.setCloseFactor(1e18 + 1);
    }
}
