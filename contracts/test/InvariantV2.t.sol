// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockToken} from "../src/mocks/MockToken.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice 状态机不变式审计：随机 Handler 驱动 LendingPool（3 市场 × 4 账户），
///         校验逐市场资金守恒与全局 tier 一致性在任意操作序列后始终成立。
contract InvariantV2Test is Test {
    LendingPool internal pool;
    MockUSDC internal usdc;
    MockToken internal usdt;
    MockToken internal dai;
    MockToken internal wsteth;
    MockToken internal wbtc;
    Handler internal handler;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint8 internal constant M_USDC = 0;
    uint8 internal constant M_USDT = 1;
    uint8 internal constant M_DAI = 2;

    function setUp() public {
        usdc = new MockUSDC();
        usdt = new MockToken("USDT", "USDT", 6);
        dai = new MockToken("DAI", "DAI", 18);
        wsteth = new MockToken("wstETH", "wstETH", 18);
        wbtc = new MockToken("WBTC", "WBTC", 8);

        MockPriceOracle oracle = new MockPriceOracle();
        oracle.setPrice(ETH, 3000e8);
        oracle.setPrice(address(usdc), 1e8);
        oracle.setPrice(address(usdt), 1e8);
        oracle.setPrice(address(dai), 1e8);
        oracle.setPrice(address(wsteth), 3000e8);
        oracle.setPrice(address(wbtc), 100_000e8);

        InterestRateModel irm = new InterestRateModel();
        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(address(usdc));
        pool = new LendingPool(usdc, oracle, irm, rm, lm, rsv);
        rsv.setLendingPool(address(pool));
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), address(this));
        pool.grantRole(pool.PAUSER_ROLE(), address(this));
        pool.addMarket(address(usdt), 6);
        pool.addMarket(address(dai), 18);
        pool.addCollateral(address(wsteth), 18);
        pool.addCollateral(address(wbtc), 8);
        _tier(rm, address(wsteth), 5e17, 6e17, 7e17, 75e16, 8e17, 6e17, 7e17, 78e16, 85e16, 9e17);
        _tier(rm, address(wbtc), 45e16, 55e16, 65e16, 7e17, 75e16, 55e16, 65e16, 75e16, 8e17, 85e16);
        irm.setMarketGovernor(address(this));

        address[] memory actors = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            actors[i] = makeAddr(string.concat("actor", vm.toString(i)));
            vm.deal(actors[i], 50 ether);
        }
        // mint & fund tokens
        usdc.faucet(1_000_000e6);
        usdt.faucet(1_000_000e6);
        dai.faucet(1_000_000e18);
        wsteth.faucet(1000 ether);
        wbtc.faucet(1000e8);
        for (uint256 i = 0; i < 4; i++) {
            address a = actors[i];
            usdc.transfer(a, 200_000e6);
            usdt.transfer(a, 200_000e6);
            dai.transfer(a, 200_000e18);
            wsteth.transfer(a, 100 ether);
            wbtc.transfer(a, 100e8);
        }

        handler = new Handler(pool, address(usdc), address(usdt), address(dai), address(wsteth), address(wbtc), actors);
        for (uint256 i = 0; i < 4; i++) {
            address a = actors[i];
            // pre-approve
            vm.prank(a);
            usdc.approve(address(pool), type(uint256).max);
            vm.prank(a);
            usdt.approve(address(pool), type(uint256).max);
            vm.prank(a);
            dai.approve(address(pool), type(uint256).max);
            vm.prank(a);
            wsteth.approve(address(pool), type(uint256).max);
            vm.prank(a);
            wbtc.approve(address(pool), type(uint256).max);
            // collateralize: ETH 1 ether + wstETH 0.1 + WBTC 0.02
            vm.prank(a);
            pool.supplyCollateral{value: 1 ether}();
            vm.prank(a);
            pool.supplyCollateral(address(wsteth), 1e17);
            vm.prank(a);
            pool.supplyCollateral(address(wbtc), 2e6);
        }
        targetContract(address(handler));
    }

    function _tier(
        RiskManager rm,
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
        for (uint256 i = 0; i < 5; i++) rm.setTier(token, i + 1, ltv[i], lt[i]);
    }

    // ==================== 不变式 ====================

    function invariant_conservation_usdc() public view {
        (uint256 cash, uint256 borrows, uint256 supply, uint256 reserve, uint256 treasury,) =
            pool.marketAccounts(M_USDC);
        uint256 lhs = cash + borrows;
        uint256 rhs = supply + reserve + treasury;
        assertApproxEqAbs(lhs, rhs, 1e6, "USDC conservation broken");
    }

    function invariant_conservation_usdt() public view {
        (uint256 cash, uint256 borrows, uint256 supply, uint256 reserve, uint256 treasury,) =
            pool.marketAccounts(M_USDT);
        assertApproxEqAbs(cash + borrows, supply + reserve + treasury, 1e6, "USDT conservation broken");
    }

    function invariant_conservation_dai() public view {
        (uint256 cash, uint256 borrows, uint256 supply, uint256 reserve, uint256 treasury,) =
            pool.marketAccounts(M_DAI);
        assertApproxEqAbs(cash + borrows, supply + reserve + treasury, 1e15, "DAI conservation broken");
    }

    /// @notice 全局 tier 一致性：有任意债务 ⇒ globalTier>0 且等于各市场 tier；无债务 ⇒ globalTier==0。
    function invariant_global_tier_consistency() public view {
        uint256 n = handler.actorsCount();
        for (uint256 i = 0; i < n; i++) {
            address u = handler.actors(i);
            uint8 gt = pool.userGlobalTier(u);
            bool any = false;
            for (uint8 m = 0; m < 3; m++) {
                uint256 d = pool.userDebtToken(u, m);
                if (d > 0) {
                    any = true;
                    assertTrue(gt > 0, "tier 0 while in debt");
                    assertEq(uint256(pool.userTier(u, m)), uint256(gt), "per-market tier mismatch");
                }
            }
            if (!any) assertEq(uint256(gt), 0, "global tier not cleared");
        }
    }
}

/// @notice 随机操作 Handler（每步以随机账户/金额执行，任意 revert 被 forge 容忍，不影响不变式）。
contract Handler {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    LendingPool public pool;
    address public immutable usdc;
    address public immutable usdt;
    address public immutable dai;
    address public immutable wsteth;
    address public immutable wbtc;
    address[] public actors;

    constructor(LendingPool pool_, address u0, address u1, address d, address w, address b, address[] memory actors_) {
        pool = pool_;
        usdc = u0;
        usdt = u1;
        dai = d;
        wsteth = w;
        wbtc = b;
        actors = actors_;
    }

    function actorsCount() external view returns (uint256) {
        return actors.length;
    }

    function _token(uint8 m) internal view returns (address) {
        if (m == 0) return usdc;
        if (m == 1) return usdt;
        return dai;
    }

    function _scale(uint8 m) internal pure returns (uint256) {
        return m == 2 ? 1e18 : 1e6;
    }

    function _pick(uint256 x, uint256 n) internal pure returns (uint256) {
        return x % n;
    }

    function op_supply(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        uint8 m = uint8(_pick(x >> 8, 3));
        uint256 units = _pick(x >> 16, 100) + 1;
        vm.prank(a);
        pool.supply(m, units * _scale(m));
    }

    function op_withdraw(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        uint8 m = uint8(_pick(x >> 8, 3));
        uint256 shares = pool.userSharesOf(a, m);
        if (shares == 0) return;
        uint256 take = shares * _pick(x >> 16, 100) / 100;
        if (take == 0) take = 1;
        (uint256 cash,,,,, uint256 supplyIndex) = pool.marketAccounts(m);
        uint256 needed = take * supplyIndex / 1e18;
        if (cash < needed) return; // 流动性不足跳过
        vm.prank(a);
        pool.withdraw(m, take);
    }

    function op_supplyCollateralEth(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        vm.prank(a);
        pool.supplyCollateral{value: (_pick(x >> 8, 10) + 1) * 1e16}();
    }

    function op_withdrawCollateralEth(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        uint256 held = pool.userCollateralOf(a, 0);
        if (held == 0) return;
        uint256 amt = held * _pick(x >> 8, 100) / 100;
        if (amt == 0) amt = 1;
        vm.prank(a);
        pool.withdrawCollateral(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, amt);
    }

    function op_borrow(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        uint8 m = uint8(_pick(x >> 8, 3));
        uint256 units = _pick(x >> 16, 200) + 1;
        vm.prank(a);
        pool.borrow(m, units * _scale(m), 1);
    }

    function op_repay(uint256 x) external {
        address a = actors[_pick(x, actors.length)];
        uint8 m = uint8(_pick(x >> 8, 3));
        uint256 debt = pool.userDebtToken(a, m);
        if (debt == 0) return;
        uint256 units = _pick(x >> 16, 300) + 1;
        uint256 amt = units * _scale(m);
        if (amt > debt) amt = debt;
        vm.prank(a);
        pool.repay(m, amt);
    }

    /// @notice 偶尔推进时间触发利息累计，验证守恒/取整容差。
    function op_accrue(uint256 x) external {
        vm.warp(block.timestamp + _pick(x, 30 days) + 1);
        pool.accrue();
    }

    function op_skim(uint256 x) external {
        uint256 m = _pick(x, 3);
        if (m != 0) return; // 仅默认市场有 skim
        vm.prank(actors[_pick(x >> 8, actors.length)]);
        pool.skimReserve();
    }
}
