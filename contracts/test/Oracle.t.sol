// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/oracle/ChainlinkOracle.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";

contract OracleTest is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event PriceAnomalyDetected(address indexed asset, uint256 lastPrice, uint256 newPrice);

    ChainlinkOracle internal oracle;
    MockAggregatorV3 internal ethFeed;
    MockAggregatorV3 internal usdcFeed;
    MockUSDC internal usdc;
    address internal usdcAddr;
    address internal admin;
    address internal pauser;
    address internal alice;

    function setUp() public {
        vm.warp(2_000_000);
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        alice = makeAddr("alice");
        usdcAddr = makeAddr("usdc");
        oracle = new ChainlinkOracle();
        oracle.grantRole(oracle.PARAM_ADMIN_ROLE(), admin);
        oracle.grantRole(oracle.PAUSER_ROLE(), pauser);
        ethFeed = new MockAggregatorV3();
        usdcFeed = new MockAggregatorV3();
        vm.prank(admin);
        oracle.setFeed(ETH, IAggregatorV3(address(ethFeed)), 8);
        vm.prank(admin);
        oracle.setFeed(usdcAddr, IAggregatorV3(address(usdcFeed)), 6);
        ethFeed.setData(3000e8, block.timestamp, 8);
        usdcFeed.setData(1_000_000, block.timestamp, 6);
        usdc = new MockUSDC();
    }

    function test_NormalPriceRead() public {
        uint256 ethPrice = oracle.updatePrice(ETH);
        assertEq(ethPrice, 3000e8);
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
        // USDC 6 位小数 feed 自动缩放到 8 位
        assertEq(oracle.getAssetPrice(usdcAddr), 1e8);
    }

    function test_StalePriceReverts() public {
        oracle.updatePrice(ETH);
        ethFeed.setData(3000e8, block.timestamp - 2 hours, 8);
        vm.expectRevert(bytes("stale price"));
        oracle.getAssetPrice(ETH);
    }

    function test_DeviationReturnsPriceAndEmitsAnomaly() public {
        oracle.updatePrice(ETH); // cache 3000
        ethFeed.setData(3000e8 * 2, block.timestamp, 8); // +100%
        // 不 revert，返回新价格
        assertEq(oracle.getAssetPrice(ETH), 6000e8);
        // updatePrice 触发 PriceAnomalyDetected
        vm.expectEmit(true, true, true, true);
        emit PriceAnomalyDetected(ETH, 3000e8, 6000e8);
        oracle.updatePrice(ETH);
    }

    function test_DeviationWithinThresholdNoAnomaly() public {
        oracle.updatePrice(ETH); // cache 3000
        ethFeed.setData(3000e8 * 12 / 10, block.timestamp, 8); // +20% < 50%
        assertEq(oracle.getAssetPrice(ETH), 3600e8);
        oracle.updatePrice(ETH); // 正常更新，无 PriceAnomalyDetected
    }

    function test_PauserCanPauseDuringAnomaly() public {
        oracle.updatePrice(ETH);
        ethFeed.setData(3000e8 * 2, block.timestamp, 8);
        // 异常价格可用
        assertEq(oracle.getAssetPrice(ETH), 6000e8);
        // PAUSER 暂停 → 读价 revert
        vm.prank(pauser);
        oracle.pause();
        vm.expectRevert(bytes("oracle paused"));
        oracle.getAssetPrice(ETH);
        vm.prank(pauser);
        oracle.unpause();
    }

    function test_FallbackAndPause() public {
        oracle.updatePrice(ETH); // cache 3000
        vm.prank(pauser);
        oracle.enableFallback();
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
        // fallback 超时
        vm.warp(block.timestamp + oracle.fallbackMaxAge() + 1);
        vm.expectRevert(bytes("fallback stale"));
        oracle.getAssetPrice(ETH);
        // pause 直接拒绝
        vm.warp(block.timestamp - oracle.fallbackMaxAge() - 1);
        vm.prank(pauser);
        oracle.pause();
        vm.expectRevert(bytes("oracle paused"));
        oracle.getAssetPrice(ETH);
        vm.prank(pauser);
        oracle.unpause();
        vm.prank(pauser);
        oracle.disableFallback();
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
    }

    function test_ParamConfigPermissionAndBounds() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, oracle.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        oracle.setMaxStaleness(1000);
        // 越界
        vm.expectRevert(bytes("staleness out of bounds"));
        vm.prank(admin);
        oracle.setMaxStaleness(100);
        // 正常
        vm.prank(admin);
        oracle.setMaxStaleness(2 hours);
        assertEq(oracle.maxStaleness(), 2 hours);
        vm.expectRevert(bytes("deviation out of bounds"));
        vm.prank(admin);
        oracle.setMaxDeviation(3e18);
    }

    function test_RemoveFeedAndSetFallbackMaxAge() public {
        vm.prank(admin);
        oracle.setFallbackMaxAge(12 hours);
        assertEq(oracle.fallbackMaxAge(), 12 hours);
        vm.expectRevert(bytes("age out of bounds"));
        vm.prank(admin);
        oracle.setFallbackMaxAge(100);
        // 移除 USDC feed 后读取 revert
        vm.prank(admin);
        oracle.removeFeed(usdcAddr);
        vm.expectRevert(bytes("no feed"));
        oracle.getAssetPrice(usdcAddr);
    }

    function test_DeviationBoundary29vs31Percent() public {
        oracle.updatePrice(ETH); // cache 3000
        // 29% < 30% → 不异常
        ethFeed.setData(3000e8 * 129 / 100, block.timestamp, 8);
        oracle.updatePrice(ETH);
        assertFalse(oracle.isPriceAnomalous(ETH));
        // 复位缓存到 3000
        ethFeed.setData(3000e8, block.timestamp, 8);
        oracle.updatePrice(ETH);
        // 31% > 30% → 异常 + 事件
        ethFeed.setData(3000e8 * 131 / 100, block.timestamp, 8);
        vm.expectEmit(true, true, true, true);
        emit PriceAnomalyDetected(ETH, 3000e8, 3000e8 * 131 / 100);
        oracle.updatePrice(ETH);
        assertTrue(oracle.isPriceAnomalous(ETH));
        // 恢复正常价 → 清除
        ethFeed.setData(3000e8, block.timestamp, 8);
        oracle.updatePrice(ETH);
        assertFalse(oracle.isPriceAnomalous(ETH));
    }

    function test_PriceAnomalyRestrictsBorrowAndCollateral() public {
        InterestRateModel irm = new InterestRateModel();
        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(address(usdc));
        LendingPool pool = new LendingPool(usdc, oracle, irm, rm, lm, rsv);
        rsv.setLendingPool(address(pool));
        vm.prank(admin);
        oracle.setFeed(address(usdc), IAggregatorV3(address(usdcFeed)), 6);

        address supplier = makeAddr("supplier");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");
        vm.deal(borrower, 3 ether); // 充足 ETH，供两次 supplyCollateral
        vm.deal(liquidator, 1 ether);
        usdc.faucet(200_000e6);
        usdc.transfer(supplier, 100_000e6);
        usdc.transfer(liquidator, 100_000e6);

        vm.prank(supplier);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(0, 100_000e6);
        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(borrower);
        pool.borrow(0, 2000e6, 5); // HF=1.35 @3000

        // 触发异常：ETH 跌到 2050（偏差 31.7% > 30%）→ 标记异常，HF=0.92 可清算
        oracle.updatePrice(ETH);
        ethFeed.setData(2050e8, block.timestamp, 8);
        oracle.updatePrice(ETH);
        assertTrue(oracle.isPriceAnomalous(ETH));

        // borrow / supplyCollateral 被禁止
        vm.prank(borrower);
        vm.expectRevert(bytes("price anomalous"));
        pool.borrow(0, 100e6, 5);
        vm.prank(borrower);
        vm.expectRevert(bytes("price anomalous"));
        pool.supplyCollateral{value: 1 ether}();

        // repay / withdraw / liquidate 正常
        vm.prank(borrower);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(borrower);
        pool.repay(0, 100e6);
        vm.prank(supplier);
        pool.withdraw(0, 1000e6);
        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(borrower, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 1000e6, 0);
        assertLt(pool.getDebt(borrower), 2000e6 * 1e12);
    }

    function test_ChainlinkIsDropInReplacement() public {
        // LendingPool 直接用 ChainlinkOracle，存/借全流程正常
        MockPriceOracle mockOracle = new MockPriceOracle();
        InterestRateModel irm = new InterestRateModel();
        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(address(usdc));
        LendingPool pool = new LendingPool(usdc, oracle, irm, rm, lm, rsv);
        rsv.setLendingPool(address(pool));

        // 池子现在会读 USDC/USD 价格，把真实 MockUSDC 的 feed 也配到 ChainlinkOracle
        vm.prank(admin);
        oracle.setFeed(address(usdc), IAggregatorV3(address(usdcFeed)), 6);

        address supplier = makeAddr("supplier");
        address borrower = makeAddr("borrower");
        vm.deal(borrower, 1 ether);
        usdc.faucet(100_000e6);
        usdc.transfer(supplier, 50_000e6);

        vm.prank(supplier);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(0, 50_000e6);
        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(borrower);
        pool.borrow(0, 1000e6, 1);
        assertGt(pool.getDebt(borrower), 0);

        // 无缝切换到 MockPriceOracle
        pool.setPriceOracle(mockOracle);
        assertEq(address(pool.priceOracle()), address(mockOracle));
    }
}
