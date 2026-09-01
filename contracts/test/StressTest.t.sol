// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";

contract StressTest is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant WAD = 1e18;

    MockUSDC internal usdc;
    MockPriceOracle internal oracle;
    InterestRateModel internal irm;
    RiskManager internal riskManager;
    LiquidationManager internal liqManager;
    ReserveManager internal reserveManager;
    LendingPool internal pool;

    address internal supplier;
    address internal liquidator;

    function setUp() public {
        supplier = makeAddr("supplier");
        liquidator = makeAddr("liquidator");
    }

    function test_StressMatrix() public {
        uint256[] memory drops = new uint256[](6);
        drops[0] = 5;
        drops[1] = 10;
        drops[2] = 20;
        drops[3] = 30;
        drops[4] = 40;
        drops[5] = 50;

        string memory md = "| Drop | Tier | Liquidation | BadDebt | Conserved | Reserve |\n";
        md = string(abi.encodePacked(md, "| --- | --- | --- | --- | --- | --- |\n"));

        for (uint256 d = 0; d < drops.length; d++) {
            for (uint256 tier = 1; tier <= 5; tier++) {
                md = string(abi.encodePacked(md, _scenario(drops[d], tier)));
            }
        }
        vm.writeFile("test-out/stress_matrix.md", md);
    }

    function _scenario(uint256 dropPct, uint256 tier) internal returns (string memory) {
        _deploy();
        address borrower = makeAddr(string(abi.encodePacked("borrower-", vm.toString(dropPct), "-", vm.toString(tier))));

        oracle.setPrice(ETH, 3000e8);
        oracle.setPrice(address(usdc), 1e8);

        usdc.faucet(2_000_000e6);
        usdc.transfer(supplier, 1_000_000e6);
        usdc.transfer(liquidator, 1_000_000e6);
        vm.deal(supplier, 1 ether);
        vm.deal(borrower, 1 ether);
        vm.deal(liquidator, 1 ether);

        vm.prank(supplier);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(1_000_000e6);

        uint256 maxLTV = riskManager.getMaxLTV(tier);
        uint256 borrowAmt = 3000e6 * maxLTV / WAD;

        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(borrower);
        pool.borrow(borrowAmt, tier);

        // accrue interest and settle risk reserve
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        if (pool.totalReserve() > 0) pool.skimReserve();

        // simulate price drop
        uint256 newPrice = 3000e8 * (100 - dropPct) / 100;
        oracle.setPrice(ETH, newPrice);

        // health factor must match independent computation
        uint256 collWad = pool.getCollateralValue(borrower);
        uint256 debtWad = pool.getDebt(borrower);
        uint256 lt = riskManager.getLiquidationThreshold(tier);
        uint256 expectedHf = debtWad == 0 ? type(uint256).max : collWad * lt / debtWad;
        uint256 poolHf = pool.getUserHealthFactor(borrower);
        assertApproxEqAbs(poolHf, expectedHf, 1e15);

        bool liquidatable = expectedHf < WAD;
        assertEq(pool.isLiquidatable(borrower), liquidatable, "liquidatable flag mismatch");

        _assertConserved();

        bool badDebt = false;
        string memory reserveRow = "-";
        if (liquidatable) {
            vm.prank(liquidator);
            usdc.approve(address(pool), type(uint256).max);
            for (uint256 i = 0; i < 10; i++) {
                (,, uint256 d,,,,) = pool.getUserPosition(borrower);
                (, uint256 c,,,,,) = pool.getUserPosition(borrower);
                if (d == 0 || c == 0) break;
                uint256 h = pool.getUserHealthFactor(borrower);
                if (h >= WAD) break;
                vm.prank(liquidator);
                try pool.liquidate(borrower, 100_000_000e6, 0) {}
                catch {
                    break;
                }
            }
            _assertConserved();

            (, uint256 finalCollateral,,,,,) = pool.getUserPosition(borrower);
            uint256 finalDebtWad = pool.getDebt(borrower);
            badDebt = (finalCollateral == 0 && finalDebtWad > 0);

            if (badDebt) {
                uint256 rsvBefore = reserveManager.balance();
                vm.prank(address(0xdead));
                pool.handleBadDebt(borrower);
                _assertConserved();
                reserveRow = rsvBefore > 0 ? "partial" : "zero";
            }
            if (!badDebt) {
                uint256 cv = pool.getCollateralValue(borrower);
                uint256 dv = pool.getDebt(borrower);
                if (dv > 0 && cv < dv) badDebt = true;
            }
        }

        bool conserved = _conserved();

        emit log_string(string(
                abi.encodePacked(
                    "[stress] drop=",
                    vm.toString(dropPct),
                    "% tier=",
                    vm.toString(tier),
                    " liquidatable=",
                    liquidatable ? "yes" : "no",
                    " badDebt=",
                    badDebt ? "yes" : "no",
                    " conserved=",
                    conserved ? "yes" : "no"
                )
            ));

        return string(
            abi.encodePacked(
                "| ",
                vm.toString(dropPct),
                "% | ",
                vm.toString(tier),
                " | ",
                liquidatable ? "YES" : "NO",
                " | ",
                badDebt ? "YES" : "NO",
                " | ",
                conserved ? "YES" : "NO",
                " | ",
                reserveRow,
                " |\n"
            )
        );
    }

    function _deploy() internal {
        usdc = new MockUSDC();
        oracle = new MockPriceOracle();
        irm = new InterestRateModel();
        riskManager = new RiskManager();
        liqManager = new LiquidationManager();
        reserveManager = new ReserveManager(address(usdc));
        pool = new LendingPool(usdc, oracle, irm, riskManager, liqManager, reserveManager);
        reserveManager.setLendingPool(address(pool));
    }

    function _assertConserved() internal {
        assertTrue(_conserved(), "accounting not conserved");
    }

    function _conserved() internal view returns (bool) {
        // invariant: cash + totalBorrows == getTotalSupply() + totalReserve + treasuryAccrued (tolerance 1 USDC)
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        if (lhs > rhs) return (lhs - rhs) <= 1e6;
        return (rhs - lhs) <= 1e6;
    }
}
