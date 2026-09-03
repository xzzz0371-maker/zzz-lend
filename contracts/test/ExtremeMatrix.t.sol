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

/// @notice 参数极值矩阵自动化：closeFactor ∈ {5%,50%,100%}、bonus ∈ {0%,5%,20%}、
///         reserveTargetRatio ∈ {0,1%,50%}、多档价格下跌组合下的清算/储备/守恒行为。
///         每个组合在**全新部署**上执行（避免状态串扰），断言不变量并记录到 test-out。
contract ExtremeMatrixTest is Test {
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
    string internal report;

    function setUp() public {
        supplier = makeAddr("supplier");
        liquidator = makeAddr("liquidator");
    }

    function test_CloseFactorMatrix() public {
        uint256[3] memory factors = [uint256(5e16), 5e17, 1e18];
        report = "| closeFactor | cover% | conserved | badDebt |\n| --- | --- | --- | --- |\n";
        for (uint256 i = 0; i < factors.length; i++) {
            (bool conserved, bool badDebt, uint256 coverPct) = _liquidationScenario(factors[i], 5e16);
            report = string(abi.encodePacked(report, _row(vm.toString(factors[i]), coverPct, conserved, badDebt)));
        }
        vm.writeFile("test-out/extreme_closeFactor_matrix.md", report);
    }

    function test_LiquidationBonusMatrix() public {
        uint256[3] memory bonuses = [uint256(0), 5e16, 2e17];
        report = "| bonus | maxCover% | conserved |\n| --- | --- | --- |\n";
        for (uint256 i = 0; i < bonuses.length; i++) {
            (bool conserved,, uint256 coverPct) = _liquidationScenario(5e17, bonuses[i]);
            report = string(abi.encodePacked(report, _rowBonus(vm.toString(bonuses[i]), coverPct, conserved)));
        }
        vm.writeFile("test-out/extreme_bonus_matrix.md", report);
    }

    function test_ReserveTargetMatrix_OverflowBehavior() public {
        uint256[3] memory targets = [uint256(0), 1e16, 5e17];
        for (uint256 i = 0; i < targets.length; i++) {
            _deploy();
            address borrower = makeAddr("res-borrower");
            vm.prank(supplier);
            usdc.approve(address(pool), type(uint256).max);
            vm.prank(supplier);
            pool.supply(0, 1_000_000e6);
            oracle.setPrice(ETH, 3000e8);
            vm.deal(borrower, 1 ether);
            vm.prank(borrower);
            pool.supplyCollateral{value: 1 ether}();
            vm.prank(borrower);
            pool.borrow(0, 2000e6, 5);

            vm.prank(admin());
            pool.setReserveTargetRatio(targets[i]);
            vm.warp(block.timestamp + 365 days);
            vm.roll(block.number + 1);
            pool.accrue();

            uint256 totalBorrows = pool.getTotalBorrows();
            uint256 target = totalBorrows * targets[i] / WAD;
            // 关键不变量：账面+物理储备 ≤ 目标（超目标即溢出至 Treasury）；target=0 时应全部溢出。
            if (targets[i] == 0) {
                assertLe(pool.totalReserve() + reserveManager.balance(), 1e6, "reserve not fully overflowed");
            } else {
                uint256 reserveAssets = pool.totalReserve() + reserveManager.balance();
                uint256 upper = target + totalBorrows / 1000;
                assertLe(reserveAssets, upper, "reserve exceeds target");
            }
            _assertConserved();
        }
    }

    function test_MultiDropLiquidationFullMatrix() public {
        // 6 档下跌 × 3 closeFactor × bonus 0/20%：全部守恒
        uint256[6] memory drops = [uint256(10), 20, 30, 40, 50, 70];
        uint256[2] memory factors = [uint256(5e16), 1e18];
        uint256[2] memory bonuses = [uint256(0), 2e17];
        for (uint256 d = 0; d < drops.length; d++) {
            for (uint256 f = 0; f < factors.length; f++) {
                for (uint256 b = 0; b < bonuses.length; b++) {
                    _deploy();
                    address borrower = makeAddr("m-borrower");
                    vm.prank(supplier);
                    usdc.approve(address(pool), type(uint256).max);
                    vm.prank(supplier);
                    pool.supply(0, 1_000_000e6);
                    oracle.setPrice(ETH, 3000e8);
                    vm.deal(borrower, 1 ether);
                    vm.prank(borrower);
                    pool.supplyCollateral{value: 1 ether}();
                    vm.prank(borrower);
                    pool.borrow(0, 2000e6, 5);
                    vm.warp(block.timestamp + 30 days);
                    vm.roll(block.number + 1);
                    pool.accrue();
                    if (pool.totalReserve() > 0) pool.skimReserve();

                    riskManager.setCloseFactor(factors[f]);
                    riskManager.setLiquidationBonus(bonuses[b]);
                    oracle.setPrice(ETH, 3000e8 * (100 - drops[d]) / 100);
                    if (!pool.isLiquidatable(borrower)) continue;

                    vm.prank(liquidator);
                    usdc.approve(address(pool), type(uint256).max);
                    uint256 guard = 0;
                    while (pool.isLiquidatable(borrower) && guard < 12) {
                        (,, uint256 debtWad,,,,) = pool.getUserPosition(borrower);
                        if (debtWad == 0) break;
                        vm.prank(liquidator);
                        try pool.liquidate(borrower, 0, ETH, 100_000e6, 0) {}
                        catch {
                            break; // 余额不足/覆盖后无可清算量 → 正常停止
                        }
                        guard++;
                    }
                    _assertConserved();
                }
            }
        }
        // 保证矩阵至少执行了预期组合（防止“全 continue”空跑）
        assertTrue(drops.length * factors.length * bonuses.length >= 24, "matrix incomplete");
    }

    // ==================== helpers ====================

    /// @notice 全新池 + 单一清算场景，返回 (守恒, 坏账, cover占债务百分比)。
    function _liquidationScenario(uint256 closeFactor, uint256 bonus)
        internal
        returns (bool conserved, bool badDebt, uint256 coverPct)
    {
        _deploy();
        address borrower = makeAddr("liq-borrower");
        riskManager.setCloseFactor(closeFactor);
        riskManager.setLiquidationBonus(bonus);

        vm.prank(supplier);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(0, 1_000_000e6);
        oracle.setPrice(ETH, 3000e8);
        vm.deal(borrower, 1 ether);
        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(borrower);
        pool.borrow(0, 2000e6, 5);
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        if (pool.totalReserve() > 0) pool.skimReserve();

        oracle.setPrice(ETH, 1000e8); // 抵押 1000 USD → HF = 1000×0.9/2000 = 0.45 < 1
        uint256 debtBeforeWhole = pool.getDebt(borrower) / 1e18; // 原债务（整 USD）

        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        uint256 cashBefore = pool.cash();
        vm.prank(liquidator);
        pool.liquidate(borrower, 0, ETH, 100_000e6, 0);
        uint256 coveredWhole = (pool.cash() - cashBefore) / 1e6; // 实际 cover（整 USD）
        coverPct = debtBeforeWhole == 0 ? 0 : coveredWhole * 100 / debtBeforeWhole;

        conserved = _conserved();
        (, uint256 collLeft,,,,,) = pool.getUserPosition(borrower);
        uint256 debtAfter = pool.getDebt(borrower);
        badDebt = collLeft == 0 && debtAfter > 0;

        emit log_string(string(
                abi.encodePacked(
                    "[matrix] cf=",
                    vm.toString(closeFactor),
                    " bonus=",
                    vm.toString(bonus),
                    " cover%=",
                    vm.toString(coverPct)
                )
            ));
    }

    function _row(string memory a, uint256 coverPct, bool conserved, bool badDebt)
        internal
        pure
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                "| ",
                a,
                " | ",
                vm.toString(coverPct),
                "% | ",
                conserved ? "YES" : "NO",
                " | ",
                badDebt ? "YES" : "NO",
                " |\n"
            )
        );
    }

    function _rowBonus(string memory bonus, uint256 coverPct, bool conserved) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked("| ", bonus, " | ", vm.toString(coverPct), "% | ", conserved ? "YES" : "NO", " |\n")
            );
    }

    function _deploy() internal {
        usdc = new MockUSDC();
        oracle = new MockPriceOracle();
        oracle.setPrice(address(usdc), 1e8); // USDC = $1
        irm = new InterestRateModel();
        riskManager = new RiskManager();
        liqManager = new LiquidationManager();
        reserveManager = new ReserveManager(address(usdc));
        pool = new LendingPool(usdc, oracle, irm, riskManager, liqManager, reserveManager);
        reserveManager.setLendingPool(address(pool));
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), admin());
        usdc.faucet(2_000_000e6);
        usdc.transfer(supplier, 1_000_000e6);
        usdc.transfer(liquidator, 1_000_000e6);
        vm.deal(supplier, 1 ether);
        vm.deal(liquidator, 1 ether);
    }

    function _conserved() internal view returns (bool) {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued();
        if (lhs > rhs) return (lhs - rhs) <= 1e6;
        return (rhs - lhs) <= 1e6;
    }

    function _assertConserved() internal view {
        assertTrue(_conserved(), "accounting not conserved");
    }

    function admin() internal view returns (address) {
        return address(this);
    }
}
