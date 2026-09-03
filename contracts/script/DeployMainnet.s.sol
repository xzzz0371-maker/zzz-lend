// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/oracle/ChainlinkOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {RiskEngine} from "../src/risk/RiskEngine.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @title ZZZ Lend 主网就绪部署模板（多签 / 真实 feed / 默认禁 settable / token 白名单）
/// @dev
///   设计目标：给“上主网”用的参数化模板。与测试网 Deploy.s.sol 的区别：
///     1. 真实 Chainlink feed（无 Mock / 无可设价）：只部署 ChainlinkOracle 直接作为池的价格源，
///        **不部署 SwitchableOracle**，因此协议中不存在“可设价”通道（默认禁 settable）。
///     2. 多签：所有角色（PARAM_ADMIN / PAUSER / Ownable）在部署完成前移交到 MAINNET_ADMIN 多签；
///        treasury 指向 MAINNET_TREASURY；部署者最后撤销自己的 DEFAULT_ADMIN 等角色。
///     3. token 白名单：仅注册 enabled 且提供了真实 feed 的资产（USDC 市场 & ETH 抵押为构造内建，必须启用）。
///     4. 预检：地址/feed 非零、代码存在性、feed 新鲜度与 decimals 在部署前校验，缺项即 revert。
///
///   用法（先填 .env 或环境变量）：
///     forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url $MAINNET_RPC_URL \
///           --broadcast --verify -vvvv
///   必填环境变量：PRIVATE_KEY / MAINNET_RPC_URL / MAINNET_ADMIN / MAINNET_TREASURY /
///           MAINNET_ETH_USD_FEED / MAINNET_USDC_TOKEN / MAINNET_USDC_USD_FEED /
///           （其余市场/抵押品按 whitelist enabled 项分别要求 token 与 feed 地址）
///   可选手动追加（非默认）：MAINNET_PAUSER（默认=admin）
///
///   ⚠️ 本模板不适用于测试网演示；Sepolia 请仍用 Deploy.s.sol。
contract DeployMainnet is Script {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct AssetConf {
        address token; // ETH 哨兵或 ERC20 地址
        address feed; // Chainlink aggregator（真实主网 feed）
        uint8 feedDecimals;
        bool enabled;
    }

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address admin = vm.envAddress("MAINNET_ADMIN");
        address treasury = vm.envAddress("MAINNET_TREASURY");
        address pauser = vm.envOr("MAINNET_PAUSER", admin);

        _require(admin != address(0), "MAINNET_ADMIN required");
        _require(treasury != address(0), "MAINNET_TREASURY required");
        _require(admin != deployer, "admin must be a multisig, not deployer");
        _require(treasury != deployer, "treasury must differ from deployer");

        // ===== whitelist 配置（enabled 项必须提供真实 feed/token） =====
        // 市场（借贷资产）：USDC 为构造基座（6dp，恒启用）；USDT/DAI 按 enabled 追加。
        bool enableUsdt = vm.envOr("ENABLE_USDT", false);
        bool enableDai = vm.envOr("ENABLE_DAI", false);
        bool enableWsteth = vm.envOr("ENABLE_WSTETH", false);
        bool enableWbtc = vm.envOr("ENABLE_WBTC", false);
        AssetConf memory usdc =
            AssetConf(vm.envAddress("MAINNET_USDC_TOKEN"), vm.envAddress("MAINNET_USDC_USD_FEED"), 8, true);
        AssetConf memory usdt = AssetConf(
            vm.envOr("MAINNET_USDT_TOKEN", address(0)), vm.envOr("MAINNET_USDT_USD_FEED", address(0)), 8, enableUsdt
        );
        AssetConf memory dai = AssetConf(
            vm.envOr("MAINNET_DAI_TOKEN", address(0)), vm.envOr("MAINNET_DAI_USD_FEED", address(0)), 8, enableDai
        );
        // 抵押品：ETH 为构造内建（恒启用）；wstETH（同 ETH 档）/WBTC（保守档）按 enabled 追加。
        AssetConf memory wsteth = AssetConf(
            vm.envOr("MAINNET_WSTETH_TOKEN", address(0)),
            vm.envOr("MAINNET_WSTETH_USD_FEED", address(0)),
            8,
            enableWsteth
        );
        AssetConf memory wbtc = AssetConf(
            vm.envOr("MAINNET_WBTC_TOKEN", address(0)), vm.envOr("MAINNET_WBTC_USD_FEED", address(0)), 8, enableWbtc
        );
        address ethFeed = vm.envAddress("MAINNET_ETH_USD_FEED");

        _preflight(usdc, "USDC", true);
        _preflight(usdt, "USDT", usdt.enabled);
        _preflight(dai, "DAI", dai.enabled);
        _preflight(AssetConf(ETH, ethFeed, 8, true), "ETH", true);
        _preflight(wsteth, "wstETH", wsteth.enabled);
        _preflight(wbtc, "WBTC", wbtc.enabled);

        vm.startBroadcast(deployerKey);

        // ===== 系统合约 =====
        ChainlinkOracle oracle = new ChainlinkOracle();
        oracle.setFeed(ETH, IAggregatorV3(ethFeed), 8);
        oracle.setFeed(usdc.token, IAggregatorV3(usdc.feed), usdc.feedDecimals);
        if (usdt.enabled) oracle.setFeed(usdt.token, IAggregatorV3(usdt.feed), usdt.feedDecimals);
        if (dai.enabled) oracle.setFeed(dai.token, IAggregatorV3(dai.feed), dai.feedDecimals);
        if (wsteth.enabled) oracle.setFeed(wsteth.token, IAggregatorV3(wsteth.feed), wsteth.feedDecimals);
        if (wbtc.enabled) oracle.setFeed(wbtc.token, IAggregatorV3(wbtc.feed), wbtc.feedDecimals);

        InterestRateModel irm = new InterestRateModel();
        irm.applyPreset(InterestRateModel.MarketPreset.NORMAL);
        irm.setMarketGovernor(admin);

        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(usdc.token);

        LendingPool pool = new LendingPool(IERC20(usdc.token), oracle, irm, rm, lm, rsv);

        // ===== 追加市场/抵押品（token 白名单落地） =====
        if (usdt.enabled) pool.addMarket(usdt.token, 6);
        if (dai.enabled) pool.addMarket(dai.token, 18);
        if (wsteth.enabled) {
            pool.addCollateral(wsteth.token, 18);
            _setRiskTiers(rm, wsteth.token, false); // 与 ETH 同表：50/60/70/75/80 LTV
        }
        if (wbtc.enabled) {
            pool.addCollateral(wbtc.token, 8);
            _setRiskTiers(rm, wbtc.token, true); // 保守表：45/55/65/70/75 LTV
        }

        // ===== RiskEngine / 接线 =====
        RiskEngine re = new RiskEngine(address(oracle), address(pool));
        rsv.setLendingPool(address(pool));
        pool.setTreasuryAddress(treasury);

        // ===== 角色：移交多签 + treasury + 撤销部署者 =====
        // pool（AccessControl）
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), admin);
        pool.grantRole(pool.PAUSER_ROLE(), pauser);
        pool.grantRole(pool.DEFAULT_ADMIN_ROLE(), admin);
        // oracle（AccessControl）
        oracle.grantRole(oracle.PARAM_ADMIN_ROLE(), admin);
        oracle.grantRole(oracle.PAUSER_ROLE(), pauser);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), admin);
        // riskEngine（AccessControl）
        re.grantRole(re.PARAM_ADMIN_ROLE(), admin);
        re.grantRole(re.DEFAULT_ADMIN_ROLE(), admin);
        // Ownable 系列
        irm.transferOwnership(admin);
        rm.transferOwnership(admin);
        rsv.transferOwnership(admin);

        // 撤销部署者：先撤子角色，最后撤 DEFAULT_ADMIN（撤后本脚本不能再做管理操作）。
        pool.renounceRole(pool.PARAM_ADMIN_ROLE(), deployer);
        pool.renounceRole(pool.PAUSER_ROLE(), deployer);
        pool.renounceRole(pool.DEFAULT_ADMIN_ROLE(), deployer);
        oracle.renounceRole(oracle.PARAM_ADMIN_ROLE(), deployer);
        oracle.renounceRole(oracle.PAUSER_ROLE(), deployer);
        oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
        re.renounceRole(re.PARAM_ADMIN_ROLE(), deployer);
        re.renounceRole(re.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        _log(
            deployer,
            admin,
            treasury,
            pauser,
            usdc,
            usdt,
            dai,
            wsteth,
            wbtc,
            ethFeed,
            oracle,
            irm,
            rm,
            lm,
            rsv,
            re,
            pool
        );

        _writeJson(
            deployer,
            admin,
            treasury,
            pauser,
            usdc,
            usdt,
            dai,
            wsteth,
            wbtc,
            ethFeed,
            oracle,
            irm,
            rm,
            lm,
            rsv,
            re,
            pool
        );
    }

    // ==================== helpers ====================

    /// @notice 预检：enabled 资产的 token/feed 非零；并做链上只读核验（代码存在 + feed 新鲜 + decimals）。
    function _preflight(AssetConf memory a, string memory symbol, bool required) internal view {
        if (!required) {
            console2.log("[skip] whitelist disabled:", symbol);
            return;
        }
        _require(a.token != address(0), string.concat(symbol, " token required"));
        _require(a.feed != address(0), string.concat(symbol, " feed required"));
        if (a.token != ETH) _require(a.token.code.length > 0, string.concat(symbol, " token has no code"));
        _require(a.feed.code.length > 0, string.concat(symbol, " feed has no code"));

        // 只在真实链上核验 feed（脚本对 feed 做只读 latestRoundData，无需广播）。
        uint8 dec = IAggregatorV3(a.feed).decimals();
        _require(dec == a.feedDecimals, string.concat(symbol, " feed decimals mismatch"));
        (, int256 answer,, uint256 updatedAt,) = IAggregatorV3(a.feed).latestRoundData();
        _require(answer > 0, string.concat(symbol, " feed invalid answer"));
        _require(
            block.timestamp >= updatedAt && block.timestamp - updatedAt <= 2 hours,
            string.concat(symbol, " feed stale (>2h)")
        );
        console2.log("[ok] preflight:", symbol, a.token);
    }

    function _setRiskTiers(RiskManager rm, address token, bool conservative) internal {
        if (conservative) {
            uint256[5] memory ltv = [uint256(45e16), 55e16, 65e16, 7e17, 75e16];
            uint256[5] memory lt = [uint256(55e16), 65e16, 75e16, 8e17, 85e16];
            for (uint256 i = 0; i < 5; i++) {
                rm.setTier(token, i + 1, ltv[i], lt[i]);
            }
        } else {
            uint256[5] memory ltv = [uint256(5e17), 6e17, 7e17, 75e16, 8e17];
            uint256[5] memory lt = [uint256(6e17), 7e17, 78e16, 85e16, 9e17];
            for (uint256 i = 0; i < 5; i++) {
                rm.setTier(token, i + 1, ltv[i], lt[i]);
            }
        }
    }

    function _require(bool cond, string memory msg_) internal pure {
        require(cond, msg_);
    }

    function _log(
        address deployer,
        address admin,
        address treasury,
        address pauser,
        AssetConf memory usdc,
        AssetConf memory usdt,
        AssetConf memory dai,
        AssetConf memory wsteth,
        AssetConf memory wbtc,
        address ethFeed,
        ChainlinkOracle oracle,
        InterestRateModel irm,
        RiskManager rm,
        LiquidationManager lm,
        ReserveManager rsv,
        RiskEngine re,
        LendingPool pool
    ) internal view {
        console2.log("=== ZZZ Lend MAINNET (template) ===");
        console2.log("Deployer:", deployer);
        console2.log("Admin(multisig):", admin);
        console2.log("Treasury:", treasury);
        console2.log("Pauser:", pauser);
        console2.log("USDC:", usdc.token);
        console2.log("USDT enabled:", usdt.enabled, usdt.token);
        console2.log("DAI enabled:", dai.enabled, dai.token);
        console2.log("wstETH enabled:", wsteth.enabled, wsteth.token);
        console2.log("WBTC enabled:", wbtc.enabled, wbtc.token);
        console2.log("ETH feed:", ethFeed);
        console2.log("ChainlinkOracle:", address(oracle));
        console2.log("InterestRateModel:", address(irm));
        console2.log("RiskManager:", address(rm));
        console2.log("LiquidationManager:", address(lm));
        console2.log("ReserveManager:", address(rsv));
        console2.log("RiskEngine:", address(re));
        console2.log("LendingPool:", address(pool));
        console2.log("NOTE: SwitchableOracle NOT deployed (settable disabled by design).");
    }

    function _writeJson(
        address deployer,
        address admin,
        address treasury,
        address pauser,
        AssetConf memory usdc,
        AssetConf memory usdt,
        AssetConf memory dai,
        AssetConf memory wsteth,
        AssetConf memory wbtc,
        address ethFeed,
        ChainlinkOracle oracle,
        InterestRateModel irm,
        RiskManager rm,
        LiquidationManager lm,
        ReserveManager rsv,
        RiskEngine re,
        LendingPool pool
    ) internal {
        string memory obj;
        obj = vm.serializeUint("root", "chainId", block.chainid);
        obj = vm.serializeAddress("root", "deployer", deployer);
        obj = vm.serializeAddress("root", "admin", admin);
        obj = vm.serializeAddress("root", "treasury", treasury);
        obj = vm.serializeAddress("root", "pauser", pauser);
        obj = vm.serializeString("root", "mode", "MAINNET_TEMPLATE");
        obj = vm.serializeAddress("root", "usdc", usdc.token);
        obj = vm.serializeAddress("root", "usdt", usdt.enabled ? usdt.token : address(0));
        obj = vm.serializeAddress("root", "dai", dai.enabled ? dai.token : address(0));
        obj = vm.serializeAddress("root", "wsteth", wsteth.enabled ? wsteth.token : address(0));
        obj = vm.serializeAddress("root", "wbtc", wbtc.enabled ? wbtc.token : address(0));
        obj = vm.serializeAddress("root", "ethUsdFeed", ethFeed);
        obj = vm.serializeAddress("root", "usdcUsdFeed", usdc.feed);
        obj = vm.serializeAddress("root", "usdtUsdFeed", usdt.feed);
        obj = vm.serializeAddress("root", "daiUsdFeed", dai.feed);
        obj = vm.serializeAddress("root", "wstethUsdFeed", wsteth.feed);
        obj = vm.serializeAddress("root", "wbtcUsdFeed", wbtc.feed);
        obj = vm.serializeAddress("root", "oracle", address(oracle));
        obj = vm.serializeAddress("root", "interestRateModel", address(irm));
        obj = vm.serializeAddress("root", "riskManager", address(rm));
        obj = vm.serializeAddress("root", "liquidationManager", address(lm));
        obj = vm.serializeAddress("root", "reserveManager", address(rsv));
        obj = vm.serializeAddress("root", "riskEngine", address(re));
        obj = vm.serializeAddress("root", "lendingPool", address(pool));
        vm.writeJson(obj, "./deployments/mainnet.json");
    }
}
