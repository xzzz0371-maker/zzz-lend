// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {RiskEngine} from "../src/risk/RiskEngine.sol";
import {BaseSetup} from "./BaseSetup.t.sol";

contract RiskEngineTest is BaseSetup {
    RiskEngine internal engine;

    function setUp() public virtual override {
        super.setUp();
        vm.warp(2_000_000);
        engine = new RiskEngine(address(oracle), address(pool));
        engine.grantRole(engine.PARAM_ADMIN_ROLE(), admin);
    }

    function test_CalculateRiskLevelAutoMatchesManual() public view {
        // 池子为空：util=0；空池按流动性 100%（WAD）处理；无采样：vol=0
        RiskEngine.RiskLevel auto1 = engine.calculateRiskLevelAuto(0.3e18, 0.6e18);
        uint256 util = pool.getUtilization();
        uint256 total = pool.getTotalSupply();
        uint256 liq = total == 0 ? 1e18 : pool.cash() * 1e18 / total;
        RiskEngine.RiskLevel manual1 = engine.getRiskLevel(0, util, 0.3e18, 0.6e18, liq);
        assertEq(uint256(auto1), uint256(manual1));
    }

    function test_CalculateRiskLevelAutoReflectsPool() public {
        // 无存款 → LOW
        assertEq(uint256(engine.calculateRiskLevelAuto(0.1e18, 0.6e18)), uint256(RiskEngine.RiskLevel.LOW));

        // 存款+借款：util 上升、流动性下降
        _supply(bob, 100_000e6);
        _supplyCollateral(alice, 2 ether);
        _borrow(alice, 3000e6, 5); // 50% LTV
        RiskEngine.RiskLevel levelAfter = engine.calculateRiskLevelAuto(0.1e18, 0.6e18);
        // 与手动一致
        RiskEngine.RiskLevel manual =
            engine.getRiskLevel(0, pool.getUtilization(), 0.1e18, 0.6e18, pool.cash() * 1e18 / pool.getTotalSupply());
        assertEq(uint256(levelAfter), uint256(manual));
        // 借更多 → util 更高 → 风险不降
        _borrow(alice, 1000e6, 5);
        RiskEngine.RiskLevel more = engine.calculateRiskLevelAuto(0.1e18, 0.6e18);
        assertGe(uint256(more), uint256(levelAfter));
    }

    function test_LowVolLowUtilLowLtv() public {
        RiskEngine.RiskLevel level = engine.getRiskLevel(0.1e18, 0.3e18, 0.3e18, 0.6e18, 0.5e18);
        assertEq(uint256(level), uint256(RiskEngine.RiskLevel.LOW));
    }

    function test_MediumVolUtilLtv() public {
        RiskEngine.RiskLevel level = engine.getRiskLevel(0.4e18, 0.6e18, 0.42e18, 0.6e18, 0.2e18);
        assertEq(uint256(level), uint256(RiskEngine.RiskLevel.MEDIUM));
    }

    function test_HighVolUtilLtv() public {
        RiskEngine.RiskLevel level = engine.getRiskLevel(0.7e18, 0.8e18, 0.54e18, 0.6e18, 0.05e18);
        assertEq(uint256(level), uint256(RiskEngine.RiskLevel.HIGH));
    }

    function test_ExtremeVolUtilLtv() public {
        RiskEngine.RiskLevel level = engine.getRiskLevel(1.2e18, 0.95e18, 0.6e18, 0.6e18, 0);
        assertEq(uint256(level), uint256(RiskEngine.RiskLevel.EXTREME));
        assertTrue(engine.isExtreme(1.2e18, 0.95e18, 0.6e18, 0.6e18, 0));
    }

    function test_VolatilityComputationAccuracy() public {
        vm.prank(admin);
        engine.setSamplingParams(3, 86400); // 3 samples, daily -> sqrt(365)
        oracle.setPrice(ETH, 100e8);
        engine.recordSample(ETH);
        vm.warp(2_000_000 + 86_400);
        oracle.setPrice(ETH, 120e8);
        engine.recordSample(ETH);
        vm.warp(2_000_000 + 2 * 86_400);
        oracle.setPrice(ETH, 108e8);
        engine.recordSample(ETH);
        assertEq(engine.getSampleCount(ETH), 3);
        // returns [0.2, -0.1] -> mean 0.05 -> std 0.15 -> annualized = 0.15 * sqrt(365) = 0.15 * 19
        uint256 annualized = engine.getAnnualizedVolatility(ETH);
        assertApproxEqAbs(annualized, 15e16 * 19, 1e14);
    }

    function test_VolatilityZeroForConstantPrices() public {
        vm.prank(admin);
        engine.setSamplingParams(3, 86400);
        oracle.setPrice(ETH, 100e8);
        engine.recordSample(ETH);
        vm.warp(2_000_000 + 86_400);
        engine.recordSample(ETH);
        vm.warp(2_000_000 + 2 * 86_400);
        engine.recordSample(ETH);
        assertEq(engine.getAnnualizedVolatility(ETH), 0);
    }

    function test_RiskEngineCannotModifyFunds() public {
        // 引擎没有任何能修改协议资金/状态的函数：任意调用不存在的选择子应 revert
        (bool ok,) = address(engine).call(abi.encodeWithSignature("setMaxBorrowTier(uint256)", 3));
        assertFalse(ok);
        (bool ok2,) = address(engine).call(abi.encodeWithSignature("applyPreset(uint8)", 1));
        assertFalse(ok2);
        assertEq(address(engine).balance, 0);
        // recordSample 只写引擎自己的采样状态，不影响资金
        oracle.setPrice(ETH, 100e8);
        engine.recordSample(ETH);
    }

    function test_ThresholdsBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, engine.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        engine.setVolThresholds(1e17, 2e17, 3e17);
        // 无序
        vm.expectRevert(bytes("not ordered"));
        vm.prank(admin);
        engine.setVolThresholds(3e17, 2e17, 1e17);
        // 越界
        vm.expectRevert(bytes("threshold out of bounds"));
        vm.prank(admin);
        engine.setVolThresholds(0, 2e17, 3e17);
        // 合法
        vm.prank(admin);
        engine.setVolThresholds(2e17, 4e17, 6e17);
        assertEq(engine.lowVolThreshold(), 2e17);
        // 采样参数边界
        vm.expectRevert(bytes("window out of bounds"));
        vm.prank(admin);
        engine.setSamplingParams(1, 3600);
        vm.expectRevert(bytes("interval out of bounds"));
        vm.prank(admin);
        engine.setSamplingParams(24, 30);
    }

    function test_InvalidLiquidityReverts() public {
        // liquidity > 1e18 (WAD) 非法
        vm.expectRevert(bytes("invalid liquidity"));
        engine.getRiskLevel(0.1e18, 0.3e18, 0.3e18, 0.6e18, 1.5e18);
        // 边界值 1e18 合法
        RiskEngine.RiskLevel level = engine.getRiskLevel(0.1e18, 0.3e18, 0.3e18, 0.6e18, 1e18);
        assertEq(uint256(level), uint256(RiskEngine.RiskLevel.LOW));
    }

    function test_RecommendationOutput() public view {
        bytes memory r1 = bytes(engine.getRecommendation(RiskEngine.RiskLevel.LOW));
        bytes memory r4 = bytes(engine.getRecommendation(RiskEngine.RiskLevel.EXTREME));
        assertGt(r4.length, r1.length);
    }
}
