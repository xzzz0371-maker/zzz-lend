// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockToken} from "../src/mocks/MockToken.sol";

/// @title Base 主网 fork dress rehearsal（chainId 8453）
/// @notice
/// 目标：在真实 Base fork 上部署“主网参数版本”合约；价格源=真实 Chainlink feed（ForkOracle 默认读真实
/// proxy，仅测试可覆写单资产价来模拟价格事件）；市场代币=本地 Mock（decimals 与 Base 真实代币一致）。
/// 背景（2026-09-03 实测）：Base 真实 USDC/USDT/DAI/cbBTC 在 foundry fork 上**读正常但 approve 写调用不可用**
/// （无 data revert、非黑名单）→ 采用“feed 真实 + 代币 Mock”（社区常规）；真实代币地址另做只读验证。
/// 运行：forge test --match-contract ForkMainnet -vvv --fork-url https://mainnet.base.org
contract ForkMainnet is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant WAD = 1e18;

    // Base 官方 Chainlink feed（真实只读）
    address internal constant FEED_ETH_USD = 0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b;
    address internal constant FEED_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address internal constant FEED_USDT_USD = 0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9;
    address internal constant FEED_DAI_USD = 0x591e79239a7d679378eC8c847e5038150364C78F;
    address internal constant FEED_CBBTC_USD = 0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D;
    // Base 官方真实代币（只读核验）
    address internal constant USDC_REAL = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant USDT_REAL = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address internal constant DAI_REAL = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;
    address internal constant CBBTC_REAL = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    uint8 internal constant M_USDC = 0;
    uint8 internal constant M_USDT = 1;
    uint8 internal constant M_DAI = 2;
    uint8 internal constant C_ETH = 0;
    uint8 internal constant C_CBBTC = 1;

    ForkOracle internal oracle;
    LendingPool internal pool;
    ReserveManager internal rsv;
    InterestRateModel internal irm;
    RiskManager internal riskManager;
    MockUSDC internal usdc;
    MockToken internal usdt;
    MockToken internal dai;
    MockToken internal cbbtc;

    function setUp() public {
        // Fork-only：非 Base 主网 fork（chainId 8453）时整组 skip，避免普通 forge test 连网报错。
        // 运行 fork：forge test --match-contract ForkMainnet --fork-url https://mainnet.base.org
        if (block.chainid != 8453) {
            vm.skip(true);
            return;
        }
        usdc = new MockUSDC();
        usdt = new MockToken("Mock Tether USD", "USDT", 6);
        dai = new MockToken("Mock Dai Stablecoin", "DAI", 18);
        cbbtc = new MockToken("Mock Coinbase Wrapped BTC", "cbBTC", 8);

        oracle = new ForkOracle();
        oracle.setFeed(ETH, FEED_ETH_USD);
        oracle.setFeed(address(usdc), FEED_USDC_USD);
        oracle.setFeed(address(usdt), FEED_USDT_USD);
        oracle.setFeed(address(dai), FEED_DAI_USD);
        oracle.setFeed(address(cbbtc), FEED_CBBTC_USD);

        irm = new InterestRateModel();
        riskManager = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        rsv = new ReserveManager(address(usdc));
        pool = new LendingPool(usdc, oracle, irm, riskManager, lm, rsv);
        rsv.setLendingPool(address(pool));
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), address(this));
        pool.grantRole(pool.PAUSER_ROLE(), address(this));

        pool.addMarket(address(usdt), 6);
        pool.addMarket(address(dai), 18);
        pool.addCollateral(address(cbbtc), 8);
        _tiers(riskManager, address(cbbtc), true);
        pool.setMarketSupplyCap(M_USDC, 1_000_000e6);
        pool.setMarketSupplyCap(M_USDT, 1_000_000e6);
        pool.setMarketSupplyCap(M_DAI, 1_000_000e18);

        usdc.faucet(10_000_000e6);
        usdt.faucet(10_000_000e6);
        dai.faucet(10_000_000e18);
        cbbtc.faucet(100_000e8);
    }

    function _tiers(RiskManager rm, address token, bool conservative) internal {
        uint256[5] memory ltv;
        uint256[5] memory lt;
        if (conservative) {
            ltv = [uint256(45e16), 55e16, 65e16, 7e17, 75e16];
            lt = [uint256(55e16), 65e16, 75e16, 8e17, 85e16];
        } else {
            ltv = [uint256(5e17), 6e17, 7e17, 75e16, 8e17];
            lt = [uint256(6e17), 7e17, 78e16, 85e16, 9e17];
        }
        for (uint256 i = 0; i < 5; i++) {
            rm.setTier(token, i + 1, ltv[i], lt[i]);
        }
    }

    // ---------- helpers ----------

    function _supply(address who, uint8 m, address t, uint256 amt) internal {
        vm.deal(who, 1 ether);
        vm.startPrank(who);
        IERC20(t).approve(address(pool), type(uint256).max);
        pool.supply(m, amt);
        vm.stopPrank();
    }

    function _supplyEth(address who, uint256 amt) internal {
        vm.deal(who, amt + 1 ether);
        vm.prank(who);
        pool.supplyCollateral{value: amt}();
    }

    function _supplyCb(address who, uint256 amt) internal {
        vm.deal(who, 1 ether);
        vm.startPrank(who);
        IERC20(address(cbbtc)).approve(address(pool), type(uint256).max);
        pool.supplyCollateral(address(cbbtc), amt);
        vm.stopPrank();
    }

    function _borrow(address who, uint8 m, uint256 amt, uint256 tier) internal {
        vm.deal(who, 1 ether);
        vm.prank(who);
        pool.borrow(m, amt, tier);
    }

    function _assertConserved(uint8 m) internal view {
        (uint256 cash, uint256 borrows, uint256 supply, uint256 reserve, uint256 treasury,) = pool.marketAccounts(m);
        uint256 lhs = cash + borrows;
        uint256 rhs = supply + reserve + treasury;
        assertApproxEqAbs(lhs, rhs, 1e6, "market conservation broken");
    }

    // ---------- 用例 ----------

    /// 真实代币只读核验 + 真实 feed 读取
    function test_ForkRealTokensAndFeedsReadable() public {
        assertEq(_symbol(USDC_REAL), "USDC");
        assertEq(_dec(USDC_REAL), 6);
        assertEq(_symbol(CBBTC_REAL), "cbBTC");
        assertEq(_dec(CBBTC_REAL), 8);
        assertEq(_symbol(DAI_REAL), "DAI");
        assertEq(_dec(DAI_REAL), 18);

        uint256 ethUsd = oracle.getAssetPrice(ETH);
        uint256 cbbtcUsd = oracle.getAssetPrice(address(cbbtc));
        assertGt(ethUsd, 0);
        assertGt(cbbtcUsd, 0);
        assertGt(ethUsd / 1e8, 2000);
        assertLt(ethUsd / 1e8, 4000);
        assertGt(cbbtcUsd / 1e8, 50_000);
        emit log_named_uint("real_eth_usd", ethUsd);
        emit log_named_uint("real_cbbtc_usd", cbbtcUsd);
    }

    /// a) 用户 A 供 10000 USDC；b) 用户 B 供 5000 USDT；c) 用户 C 供 8000 DAI
    function test_ForkSupplyThreeMarkets() public {
        address A = makeAddr("A");
        vm.deal(A, 1 ether);
        address B = makeAddr("B");
        vm.deal(B, 1 ether);
        address C = makeAddr("C");
        vm.deal(C, 1 ether);
        usdc.transfer(A, 10_000e6);
        usdt.transfer(B, 5_000e6);
        dai.transfer(C, 8_000e18);
        _supply(A, M_USDC, address(usdc), 10_000e6);
        _supply(B, M_USDT, address(usdt), 5_000e6);
        _supply(C, M_DAI, address(dai), 8_000e18);
        assertEq(pool.userSharesOf(A, M_USDC), 10_000e6);
        assertEq(pool.userSharesOf(B, M_USDT), 5_000e6);
        assertEq(pool.userSharesOf(C, M_DAI), 8_000e18);
        _assertConserved(M_USDC);
        _assertConserved(M_USDT);
        _assertConserved(M_DAI);
    }

    /// d) 用户 D 抵押 10 ETH，借 5000 USDC（Tier3）；e) 用户 E 抵押 0.2 cbBTC，借 2000 USDT（Tier2）
    function test_ForkCollateralizedBorrowing() public {
        address sup = makeAddr("sup");
        vm.deal(sup, 1 ether);
        address D = makeAddr("D");
        vm.deal(D, 1 ether);
        address E = makeAddr("E");
        vm.deal(E, 1 ether);
        usdc.transfer(sup, 200_000e6);
        usdt.transfer(sup, 100_000e6);
        _supply(sup, M_USDC, address(usdc), 200_000e6);
        _supply(sup, M_USDT, address(usdt), 100_000e6);

        _supplyEth(D, 10 ether); // ~$25k
        _borrow(D, M_USDC, 5000e6, 3);
        assertGt(pool.getDebt(D), 0);
        assertEq(uint256(pool.userGlobalTier(D)), 3);
        _assertConserved(M_USDC);

        usdc.transfer(E, 5000e6);
        _supply(E, M_USDC, address(usdc), 5000e6); // E 提供流动性（可选）
        cbbtc.transfer(E, 0.2e8);
        _supplyCb(E, 0.2e8); // ~$16k, tier2 LTV55% → cap 8.8k
        _borrow(E, M_USDT, 2000e6, 2);
        assertGt(pool.getDebt(E), 0);
        assertEq(uint256(pool.userGlobalTier(E)), 2);
        _assertConserved(M_USDT);
    }

    /// g) 用户 D 还款 2000 USDC
    function test_ForkRepayPartial() public {
        address sup = makeAddr("sup");
        vm.deal(sup, 1 ether);
        address D = makeAddr("D");
        vm.deal(D, 1 ether);
        usdc.transfer(sup, 200_000e6);
        _supply(sup, M_USDC, address(usdc), 200_000e6);
        _supplyEth(D, 5 ether);
        _borrow(D, M_USDC, 4000e6, 3);
        uint256 debt0 = pool.getDebt(D);
        vm.startPrank(D);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(M_USDC, 2000e6);
        vm.stopPrank();
        assertLt(pool.getDebt(D), debt0);
        _assertConserved(M_USDC);
    }

    /// h) 用户 A 提现 3000 USDC
    function test_ForkWithdraw() public {
        address A = makeAddr("A");
        vm.deal(A, 1 ether);
        usdc.transfer(A, 30_000e6);
        _supply(A, M_USDC, address(usdc), 30_000e6);
        uint256 bal0 = usdc.balanceOf(A);
        uint256 shares = pool.userSharesOf(A, M_USDC);
        uint256 want = 3000e6 * 1e18 / pool.supplyIndex();
        vm.prank(A);
        pool.withdraw(M_USDC, want);
        assertEq(usdc.balanceOf(A), bal0 + 3000e6);
        assertLt(pool.userSharesOf(A, M_USDC), shares);
        _assertConserved(M_USDC);
    }

    /// i/j) ETH 暴跌 30% → 触发清算，验证 bonus/seize/HF
    function test_ForkLiquidationAfterPriceDrop() public {
        address sup = makeAddr("sup");
        vm.deal(sup, 1 ether);
        address D = makeAddr("D");
        vm.deal(D, 1 ether);
        address liq = makeAddr("liq");
        vm.deal(liq, 1 ether);
        usdc.transfer(sup, 500_000e6);
        _supply(sup, M_USDC, address(usdc), 500_000e6);
        _supplyEth(D, 2 ether); // ~$5k
        _borrow(D, M_USDC, 3000e6, 5); // 80% of 5000=4000 → 3000 ok; HF=5000*.9/3000=1.5
        uint256 ethNow = oracle.getAssetPrice(ETH);
        oracle.setOverride(ETH, ethNow * 55 / 100); // -45% → HF<1
        assertTrue(pool.isLiquidatable(D), "should be liquidatable after -45%");

        uint256 collBefore = pool.userCollateralOf(D, C_ETH);
        uint256 debtBefore = pool.getDebt(D);
        usdc.transfer(liq, 5000e6);
        vm.startPrank(liq);
        usdc.approve(address(pool), type(uint256).max);
        pool.liquidate(D, M_USDC, ETH, 1000e6, 0); // 清算 1000 USDC
        vm.stopPrank();

        assertLt(pool.userCollateralOf(D, C_ETH), collBefore);
        assertLt(pool.getDebt(D), debtBefore);
        // 清算人获得 ETH
        assertGt(liq.balance, 0);
        oracle.clearOverride(ETH);
        _assertConserved(M_USDC);
    }

    /// 坏账：抵押清空仍留债 → handleBadDebt 吸收，守恒
    function test_ForkBadDebtHandled() public {
        address sup = makeAddr("sup");
        vm.deal(sup, 1 ether);
        address B = makeAddr("B");
        vm.deal(B, 1 ether);
        address liq = makeAddr("liq");
        vm.deal(liq, 1 ether);
        usdc.transfer(sup, 500_000e6);
        _supply(sup, M_USDC, address(usdc), 500_000e6);
        _supplyEth(B, 1 ether); // ~$2500
        _borrow(B, M_USDC, 2000e6, 5);
        oracle.setOverride(ETH, 1e8); // ETH≈0 → 抵押近 0
        assertTrue(pool.isLiquidatable(B));
        usdc.transfer(liq, 5000e6);
        vm.startPrank(liq);
        usdc.approve(address(pool), type(uint256).max);
        // ETH≈$1：单次清算 cover 足额即清空 1 ETH 抵押并留残债 → 走坏账
        pool.liquidate(B, M_USDC, ETH, type(uint256).max, 0);
        vm.stopPrank();
        (, uint256 collLeft, uint256 debtLeft,,,,) = pool.getUserPosition(B);
        if (collLeft == 0 && debtLeft > 0) {
            pool.handleBadDebt(B, M_USDC);
            assertEq(pool.getDebt(B), 0);
        } else {
            // 若一次未清空抵押，循环清算至清空
            uint256 guard = 0;
            while (pool.userCollateralOf(B, C_ETH) > 0 && guard < 5) {
                vm.startPrank(liq);
                pool.liquidate(B, M_USDC, ETH, type(uint256).max, 0);
                vm.stopPrank();
                guard++;
            }
            if (pool.getDebt(B) > 0 && pool.userCollateralOf(B, C_ETH) == 0) {
                pool.handleBadDebt(B, M_USDC);
            }
            assertEq(pool.getDebt(B), 0);
        }
        oracle.clearOverride(ETH);
        _assertConserved(M_USDC);
    }

    /// cbBTC 抵押借款 + 60% 跌清算（跨资产：cbBTC 抵押清 USDC 债）
    function test_ForkCbbtcLiquidationCrossAsset() public {
        address sup = makeAddr("sup");
        vm.deal(sup, 1 ether);
        address F = makeAddr("F");
        vm.deal(F, 1 ether);
        address liq = makeAddr("liq");
        vm.deal(liq, 1 ether);
        usdc.transfer(sup, 500_000e6);
        _supply(sup, M_USDC, address(usdc), 500_000e6);
        cbbtc.transfer(F, 0.3e8); // ~$24k, tier1 LTV45% → cap ~10.8k
        _supplyCb(F, 0.3e8);
        _borrow(F, M_USDC, 3000e6, 1);
        uint256 cb = oracle.getAssetPrice(address(cbbtc));
        // HF<1 需要 0.3×price×LT55% < 3000 → price < $18182（现价 30% 以下）；用 15%
        oracle.setOverride(address(cbbtc), cb * 15 / 100);
        assertTrue(pool.isLiquidatable(F), "cbBTC position should be liquidatable after -85%");
        usdc.transfer(liq, 5000e6);
        vm.startPrank(liq);
        usdc.approve(address(pool), type(uint256).max);
        pool.liquidate(F, M_USDC, address(cbbtc), 1000e6, 0);
        vm.stopPrank();
        assertLt(pool.userCollateralOf(F, C_CBBTC), 0.3e8);
        oracle.clearOverride(address(cbbtc));
        _assertConserved(M_USDC);
    }

    // ---------- read helpers ----------
    function _symbol(address t) internal view returns (string memory) {
        (bool ok, bytes memory r) = t.staticcall(abi.encodeWithSignature("symbol()"));
        require(ok, "symbol fail");
        return abi.decode(r, (string));
    }

    function _dec(address t) internal view returns (uint8) {
        (bool ok, bytes memory r) = t.staticcall(abi.encodeWithSignature("decimals()"));
        require(ok, "dec fail");
        return abi.decode(r, (uint8));
    }
}

/// @notice Fork 价格源：默认读真实 Chainlink proxy；测试可覆写单资产价模拟价格事件。
/// 每个 feed 均做 answer>0 校验（stale 由 fork 的 ChainlinkOracle 语义处理：本 wrapper 只读）。
contract ForkOracle is IPriceOracle {
    mapping(address => address) public feeds;
    mapping(address => uint256) public overrides;

    function setFeed(address asset, address feed) external {
        feeds[asset] = feed;
    }

    function setOverride(address asset, uint256 price) external {
        overrides[asset] = price;
    }

    function clearOverride(address asset) external {
        delete overrides[asset];
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        uint256 o = overrides[asset];
        if (o != 0) return o;
        (, int256 answer,,,) = IAggregatorV3(feeds[asset]).latestRoundData();
        require(answer > 0, "bad feed");
        return uint256(answer);
    }

    function isPriceAnomalous(address) external pure override returns (bool) {
        return false;
    }
}

interface IAggregatorV3 {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
