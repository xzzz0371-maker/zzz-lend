// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IInterestRateModel} from "../src/InterestRateModel.sol";
import {IRiskManager} from "../src/RiskManager.sol";
import {ILiquidationManager} from "../src/LiquidationManager.sol";
import {IReserveManager} from "../src/ReserveManager.sol";
import {SwitchableOracle} from "../src/oracle/SwitchableOracle.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/oracle/ChainlinkOracle.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";

/// @notice 安全审计报告 v1.0 修复项（F1/F2/F3/F4/F5/F9）回归测试。
contract SecurityFixesTest is BaseSetup {
    ChainlinkOracle internal clOracle;
    MockAggregatorV3 internal clEthFeed;
    MockAggregatorV3 internal clUsdcFeed;

    /// @dev 把池子价格源换成真实 ChainlinkOracle（配 mock feed），返回该 oracle。
    function _setupPoolWithChainlinkOracle() internal {
        clOracle = new ChainlinkOracle();
        clEthFeed = new MockAggregatorV3();
        clUsdcFeed = new MockAggregatorV3();
        clEthFeed.setData(3000e8, block.timestamp, 8);
        clUsdcFeed.setData(1_000_000, block.timestamp, 6);
        clOracle.setFeed(ETH, IAggregatorV3(address(clEthFeed)), 8);
        clOracle.setFeed(address(usdc), IAggregatorV3(address(clUsdcFeed)), 6);
        vm.prank(admin);
        pool.setPriceOracle(clOracle);
    }

    function _conserved() internal view returns (bool) {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        return lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6;
    }

    /// @dev 制造"存款人全损"（supplyIndex 归零）状态：单借款人借满 100% 利用率，债务随利息超过净资产。
    function _wipeDepositors() internal {
        _supply(bob, 2400e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2400e6, 5); // 借满 → cash=0, 利用率 100%
        vm.warp(block.timestamp + 365 days * 10);
        vm.roll(block.number + 1);
        pool.accrue();
        oracle.setPrice(ETH, 1e8); // 抵押归零
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 200e6, 0); // 留 200 USDC 现金供后续 MIN_BORROW
        uint256 debt = pool.getDebt(alice) / 1e12;
        uint256 supply = pool.getTotalSupply();
        assertGt(debt, supply); // 债务 > 净资产 → 全额传导
        vm.prank(address(0xdead));
        pool.handleBadDebt(alice, 0);
        assertLt(pool.supplyIndex(), 1e17); // D1后储备优先兜底，存款人残余极小
        assertGt(pool.cash(), 100e6);
    }

    // ==================== F1：repay/liquidate 取整下溢 ====================
    // 说明：v1.2 加入最小金额限制（MIN_BORROW=100e6）后，微额借款不可再创建，F1 下溢结构性不可达；
    // 封顶逻辑保留作纵深防御，以下用例验证最小金额借款的还款/清算路径正常。

    function test_F1_MinBorrowFullRepayWorks() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 100e6, 5); // 最小借款 100 USDC
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        pool.accrue(); // borrowIndex > WAD
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(0, type(uint256).max);
        assertEq(pool.getDebt(alice), 0);
        (,,,,, uint256 tier,) = pool.getUserPosition(alice);
        assertEq(tier, 0);
        assertTrue(_conserved());
    }

    function test_F1_MinBorrowLiquidationWorks() public {
        riskManager.setCloseFactor(1e18); // 100% closeFactor，全额覆盖
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 0.05 ether); // ≥ MIN_COLLATERAL，价值 150
        _borrow(alice, 100e6, 5); // 最小借款，LTV = 100/150 = 66.7%
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        pool.accrue();
        oracle.setPrice(ETH, 1000e8); // 抵押 50，HF = 50×0.9/100 = 0.45 < 1
        assertTrue(pool.isLiquidatable(alice));
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1e12, 0); // 全额覆盖 → 清债，不 revert
        assertEq(pool.getDebt(alice), 0);
        assertTrue(_conserved());
    }

    function test_F1_NormalBorrowUnaffected() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 1000e6, 5);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 1);
        pool.accrue();
        _approveUsdc(alice, type(uint256).max);
        vm.prank(alice);
        pool.repay(0, type(uint256).max);
        assertEq(pool.getDebt(alice), 0);
        // 正常规模清算不受影响
        _supplyCollateral(bob, 2 ether);
        _borrow(bob, 2000e6, 5);
        oracle.setPrice(ETH, 1000e8); // HF = 2000×0.9/2000 = 0.9 < 1
        assertTrue(pool.isLiquidatable(bob));
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(bob, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0);
        assertGt(pool.getDebt(bob), 0);
        assertLt(pool.getDebt(bob), 2000e6 * 1e12);
        assertTrue(_conserved());
    }

    // ==================== F3：SwitchableOracle.setPrice 校验 ====================

    function test_F3_SetPriceZeroReverts() public {
        SwitchableOracle so = new SwitchableOracle(oracle);
        vm.expectRevert(bytes("price must be > 0"));
        so.setPrice(ETH, 0);
    }

    function test_F3_SetPriceAboveUpperBoundReverts() public {
        SwitchableOracle so = new SwitchableOracle(oracle);
        vm.expectRevert(bytes("price out of range"));
        so.setPrice(ETH, 1e15);
    }

    function test_F3_SetPriceBelowLowerBoundReverts() public {
        SwitchableOracle so = new SwitchableOracle(oracle);
        vm.expectRevert(bytes("price out of range"));
        so.setPrice(ETH, 1e1);
    }

    function test_F3_NormalPricesOk() public {
        SwitchableOracle so = new SwitchableOracle(oracle);
        so.setPrice(ETH, 3000e8);
        so.setPrice(address(usdc), 1e8);
        assertEq(so.settablePrice(ETH), 3000e8);
        assertEq(so.settablePrice(address(usdc)), 1e8);
    }

    // ==================== F4：模块 setter 零地址/合约校验 ====================

    function test_F4_ModuleSettersZeroAddressReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setPriceOracle(IPriceOracle(address(0)));
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setInterestRateModel(IInterestRateModel(address(0)));
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setRiskManager(IRiskManager(address(0)));
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setLiquidationManager(ILiquidationManager(address(0)));
        vm.prank(admin);
        vm.expectRevert(bytes("zero address"));
        pool.setReserveManager(IReserveManager(address(0)));
    }

    function test_F4_ReserveManagerNonContractReverts() public {
        vm.prank(admin);
        vm.expectRevert(bytes("not a contract"));
        pool.setReserveManager(IReserveManager(makeAddr("eoa")));
    }

    function test_F4_ValidSwapStillWorks() public {
        vm.prank(admin);
        pool.setPriceOracle(oracle);
        assertEq(address(pool.priceOracle()), address(oracle));
        vm.prank(admin);
        pool.setReserveManager(reserveManager);
        assertEq(address(pool.reserveManager()), address(reserveManager));
    }

    // ==================== F2：坏账超额损失级联吸收（守恒始终成立） ====================

    function test_F2_ExcessLossConservationHolds() public {
        _wipeDepositors();
        assertLt(pool.supplyIndex(), 1e17); // D1后储备优先兜底，存款人残余极小
        assertTrue(_conserved(), "conservation broken after excess loss");
    }

    function test_F2_NoDepositorsConservationHolds() public {
        _wipeDepositors();
        assertLt(pool.getTotalSupply(), 1e9); // D1后储备优先兜底，存款人残余极小
        // 无存款人时再出现坏账：损失由账面储备/Treasury 兜底，守恒仍成立
        oracle.setPrice(ETH, 3000e8); // 重置价格供 carol 借款
        address carol = makeAddr("carol");
        vm.deal(carol, 2 ether);
        vm.prank(carol);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(carol);
        pool.borrow(0, 100e6, 5); // MIN_BORROW
        oracle.setPrice(ETH, 50e8); // 砸盘 → HF=0.45，且 50% 覆盖可清空抵押
        assertTrue(pool.isLiquidatable(carol));
        _approveUsdc(liquidator, type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(carol, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 50e6, 0); // 覆盖 50 USDC → 抵押清零、残留债务
        (, uint256 coll,,,,,) = pool.getUserPosition(carol);
        assertEq(coll, 0);
        assertGt(pool.getDebt(carol), 0);
        vm.prank(address(0xdead));
        pool.handleBadDebt(carol, 0);
        assertTrue(_conserved(), "conservation broken when no depositors");
    }

    // ==================== F5：ChainlinkOracle 实时偏差 + fallback ====================

    function test_F5_LiveDeviationWithoutUpdatePrice() public {
        _setupPoolWithChainlinkOracle();
        clOracle.updatePrice(ETH); // 建立基准价 3000
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        clEthFeed.setData(1500e8, block.timestamp, 8); // -50%，**不**调 updatePrice
        // isPriceAnomalous 实时检测到偏差
        assertTrue(clOracle.isPriceAnomalous(ETH));
        // LendingPool._oracleAnomalous() → 新增敞口被阻断
        vm.prank(alice);
        vm.expectRevert(bytes("price anomalous"));
        pool.borrow(0, 100e6, 1);
        vm.prank(alice);
        vm.expectRevert(bytes("price anomalous"));
        pool.supplyCollateral{value: 1 ether}();
    }

    function test_F5_FallbackUsesCachedPriceAndFlag() public {
        _setupPoolWithChainlinkOracle();
        clOracle.updatePrice(ETH); // cache 3000
        clEthFeed.setData(100e8, block.timestamp, 8); // 大幅下跌
        clOracle.enableFallback(); // PAUSER 开启 fallback
        // fallback 返回缓存价（冻结旧价），isPriceAnomalous 用缓存标记（非实时）
        assertEq(clOracle.getAssetPrice(ETH), 3000e8);
        assertFalse(clOracle.isPriceAnomalous(ETH));
        clOracle.disableFallback();
        assertEq(clOracle.getAssetPrice(ETH), 100e8); // 关回后读实时
    }

    // ==================== 最小金额限制（dust limit，v1.2） ====================

    function test_DustLimit_SupplyBelowMinReverts() public {
        _approveUsdc(alice, 10e6);
        vm.prank(alice);
        vm.expectRevert(bytes("amount below min"));
        pool.supply(0, 10e6 - 1);
    }

    function test_DustLimit_BorrowBelowMinReverts() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        vm.expectRevert(bytes("amount below min"));
        _borrow(alice, 100e6 - 1, 5);
    }

    function test_DustLimit_CollateralBelowMinReverts() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(bytes("value below min"));
        pool.supplyCollateral{value: 0.01 ether - 1}();
    }

    function test_DustLimit_SupplyAndCollateralMinWork() public {
        _supply(alice, 10e6); // = MIN_SUPPLY
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        pool.supplyCollateral{value: 0.01 ether}(); // = MIN_COLLATERAL
        assertEq(pool.totalShares(), 10e6);
        (, uint256 coll,,,,,) = pool.getUserPosition(alice);
        assertEq(coll, 0.01 ether);
        assertTrue(_conserved());
    }

    function test_DustLimit_BorrowMinWorks() public {
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 100e6, 1); // = MIN_BORROW
        assertApproxEqAbs(pool.getDebt(alice) / 1e12, 100e6, 1);
        assertTrue(_conserved());
    }

    // ==================== F9：oracle 暂停阻断清算（设计取舍文档化） ====================

    function test_F9_OraclePauseBlocksLiquidation() public {
        _setupPoolWithChainlinkOracle();
        clOracle.updatePrice(ETH);
        clOracle.updatePrice(address(usdc));
        _supply(bob, 200_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        clEthFeed.setData(1800e8, block.timestamp, 8); // -40% → HF<1
        assertTrue(pool.isLiquidatable(alice));

        _approveUsdc(liquidator, type(uint256).max);
        clOracle.pause();
        vm.prank(liquidator);
        vm.expectRevert(bytes("oracle paused"));
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0);

        clOracle.unpause();
        vm.prank(liquidator);
        pool.liquidate(alice, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0); // 恢复后清算成功
        assertLt(pool.getDebt(alice), 2000e6 * 1e12);
    }
}
