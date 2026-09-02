// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockWstETH} from "../src/mocks/MockWstETH.sol";
import {MockWBTC} from "../src/mocks/MockWBTC.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {MockDAI} from "../src/mocks/MockDAI.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice V2 多资产测试基座：在 BaseSetup（USDC 市场 + ETH 抵押）之上注册
///         USDT/DAI 借贷市场与 wstETH/WBTC 抵押资产，并配置对应 oracle 价格与档位参数。
abstract contract BaseSetupV2 is BaseSetup {
    uint8 internal constant M_USDC = 0;
    uint8 internal constant M_USDT = 1;
    uint8 internal constant M_DAI = 2;
    uint8 internal constant C_ETH = 0;
    uint8 internal constant C_WSTETH = 1;
    uint8 internal constant C_WBTC = 2;

    MockUSDT internal usdt;
    MockDAI internal dai;
    MockWstETH internal wsteth;
    MockWBTC internal wbtc;

    address internal carol;

    function setUp() public virtual override {
        BaseSetup.setUp();
        carol = makeAddr("carol");

        usdt = new MockUSDT();
        dai = new MockDAI();
        wsteth = new MockWstETH();
        wbtc = new MockWBTC();

        // oracle 价格
        oracle.setPrice(address(wsteth), 3000e8); // wstETH/USD ≈ ETH/USD (1:1 锚定)
        oracle.setPrice(address(wbtc), 100_000e8);
        oracle.setPrice(address(usdt), 1e8);
        oracle.setPrice(address(dai), 1e8);

        // 注册借贷市场（USDT 6 位、DAI 18 位）
        vm.prank(admin);
        pool.addMarket(address(usdt), 6);
        vm.prank(admin);
        pool.addMarket(address(dai), 18);

        // 注册抵押资产（wstETH 18 位、WBTC 8 位）
        vm.prank(admin);
        pool.addCollateral(address(wsteth), 18);
        vm.prank(admin);
        pool.addCollateral(address(wbtc), 8);

        // RiskManager：wstETH 同 ETH；WBTC 保守表
        _setCollateralTiers(address(wsteth), 5e17, 6e17, 7e17, 75e16, 8e17, 6e17, 7e17, 78e16, 85e16, 9e17);
        _setCollateralTiers(address(wbtc), 45e16, 55e16, 65e16, 7e17, 75e16, 55e16, 65e16, 75e16, 8e17, 85e16);

        // 铸币分发
        usdt.faucet(10_000_000e6);
        dai.faucet(10_000_000e18);
        wsteth.faucet(10_000 ether);
        wbtc.faucet(10_000e8);
        vm.deal(carol, 1000 ether);
        usdt.transfer(alice, 500_000e6);
        usdt.transfer(bob, 500_000e6);
        usdt.transfer(liquidator, 500_000e6);
        usdt.transfer(carol, 500_000e6);
        dai.transfer(alice, 500_000e18);
        dai.transfer(bob, 500_000e18);
        dai.transfer(liquidator, 500_000e18);
        dai.transfer(carol, 500_000e18);
        wsteth.transfer(alice, 500 ether);
        wsteth.transfer(bob, 500 ether);
        wsteth.transfer(liquidator, 500 ether);
        wsteth.transfer(carol, 500 ether);
        wbtc.transfer(alice, 500e8);
        wbtc.transfer(bob, 500e8);
        wbtc.transfer(liquidator, 500e8);
        wbtc.transfer(carol, 500e8);
    }

    function _setCollateralTiers(
        address token,
        uint256 l1,
        uint256 l2,
        uint256 l3,
        uint256 l4,
        uint256 l5,
        uint256 t1,
        uint256 t2,
        uint256 t3,
        uint256 t4,
        uint256 t5
    ) internal {
        uint256[5] memory ltv = [l1, l2, l3, l4, l5];
        uint256[5] memory lt = [t1, t2, t3, t4, t5];
        for (uint256 i = 0; i < 5; i++) {
            riskManager.setTier(token, i + 1, ltv[i], lt[i]);
        }
    }

    // ==================== helpers ====================

    function _approveToken(address token, address who, uint256 amount) internal {
        vm.prank(who);
        MockToken(token).approve(address(pool), amount);
    }

    function _supplyMarket(address token, uint8 marketId, address who, uint256 amount) internal {
        _approveToken(token, who, amount);
        vm.prank(who);
        pool.supply(marketId, amount);
    }

    function _supplyCollateralAsset(address token, address who, uint256 amount) internal {
        _approveToken(token, who, amount);
        vm.prank(who);
        pool.supplyCollateral(token, amount);
    }

    function _borrowMarket(uint8 marketId, address who, uint256 amount, uint256 tier) internal {
        vm.prank(who);
        pool.borrow(marketId, amount, tier);
    }

    /// @notice 市场级资金守恒：cash + borrows == supply + reserve + treasury（token 单位）。
    function _assertMarketConservation(uint8 marketId) internal view {
        (uint256 cash_, uint256 borrows_, uint256 supply_, uint256 reserve_, uint256 treasury_,) =
            pool.marketAccounts(marketId);
        uint256 lhs = cash_ + borrows_;
        uint256 rhs = supply_ + reserve_ + treasury_;
        assertEq(lhs, rhs, "market conservation broken");
    }

    /// @notice 坏账传导会因 supplyIndex 取整产生微小余数，容忍给定偏差。
    function _assertMarketConservationApprox(uint8 marketId, uint256 tol) internal view {
        (uint256 cash_, uint256 borrows_, uint256 supply_, uint256 reserve_, uint256 treasury_,) =
            pool.marketAccounts(marketId);
        uint256 lhs = cash_ + borrows_;
        uint256 rhs = supply_ + reserve_ + treasury_;
        assertApproxEqAbs(lhs, rhs, tol, "market conservation approx broken");
    }

    // 便捷：市场级读数
    function _marketCash(uint8 m) internal view returns (uint256) {
        (uint256 cash_,,,,,) = pool.marketAccounts(m);
        return cash_;
    }

    function _marketBorrows(uint8 m) internal view returns (uint256) {
        (, uint256 b,,,,) = pool.marketAccounts(m);
        return b;
    }

    function _marketSupply(uint8 m) internal view returns (uint256) {
        (,, uint256 s,,,) = pool.marketAccounts(m);
        return s;
    }

    function _marketReserve(uint8 m) internal view returns (uint256) {
        (,,, uint256 r,,) = pool.marketAccounts(m);
        return r;
    }
}
