// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {ChainlinkOracle, IAggregatorV3} from "../src/oracle/ChainlinkOracle.sol";
import {SwitchableOracle} from "../src/oracle/SwitchableOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {RiskEngine} from "../src/risk/RiskEngine.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @title ZZZ Lend Sepolia
/// @dev
///   forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
///          SEPOLIA_RPC_URL / PRIVATE_KEY / ETHERSCAN_API_KEY /
///                 SEPOLIA_ETH_USD_FEED / SEPOLIA_USDC_USD_FEED / [TESTNET_ADMIN]
///          ./deployments/sepolia.json
contract Deploy is Script {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address testnetAdmin = vm.envOr("TESTNET_ADMIN", deployer);
        // 本地验证开关：MOCK_FEEDS=1 时部署并启用模拟聚合器（不用真实 Chainlink）
        bool mockFeeds = vm.envOr("MOCK_FEEDS", false);
        address ethUsdFeed = vm.envAddress("SEPOLIA_ETH_USD_FEED");
        address usdcUsdFeed = vm.envAddress("SEPOLIA_USDC_USD_FEED");

        vm.startBroadcast(deployerKey);

        // 1. MockUSDC (6 decimals, testnet only)
        MockUSDC usdc = new MockUSDC();

        // 1b. Optional: local mock aggregators (price 3000 / 1.00 USD)
        if (mockFeeds) {
            MockAggregatorV3 ethAgg = new MockAggregatorV3();
            ethAgg.setData(3000e8, block.timestamp, 8);
            MockAggregatorV3 usdcAgg = new MockAggregatorV3();
            usdcAgg.setData(1e8, block.timestamp, 8);
            ethUsdFeed = address(ethAgg);
            usdcUsdFeed = address(usdcAgg);
        }

        // 2. ChainlinkOracle + MockPriceOracle (liquidation demo fallback)
        ChainlinkOracle oracle = new ChainlinkOracle();
        oracle.setFeed(ETH, IAggregatorV3(ethUsdFeed), 8);
        oracle.setFeed(address(usdc), IAggregatorV3(usdcUsdFeed), 8);
        oracle.grantRole(oracle.PARAM_ADMIN_ROLE(), testnetAdmin);
        oracle.grantRole(oracle.PAUSER_ROLE(), testnetAdmin);
        MockPriceOracle mockOracle = new MockPriceOracle();

        // 2b. SwitchableOracle：池子默认走真实 Chainlink；PAUSER 可切换到管理员可设价模式做清算演示
        SwitchableOracle switchable = new SwitchableOracle(oracle);
        switchable.grantRole(switchable.PARAM_ADMIN_ROLE(), testnetAdmin);
        switchable.grantRole(switchable.PAUSER_ROLE(), testnetAdmin);

        // 3. InterestRateModel NORMAL
        InterestRateModel irm = new InterestRateModel();
        irm.applyPreset(InterestRateModel.MarketPreset.NORMAL);
        irm.setMarketGovernor(testnetAdmin);
        irm.transferOwnership(testnetAdmin);

        // 4. RiskManager    LTV
        RiskManager rm = new RiskManager();
        rm.transferOwnership(testnetAdmin);

        // 5. LiquidationManager
        LiquidationManager lm = new LiquidationManager();

        // 6. ReserveManager
        ReserveManager rsv = new ReserveManager(address(usdc));

        // 7. LendingPool（价格源 = SwitchableOracle）
        LendingPool pool = new LendingPool(usdc, switchable, irm, rm, lm, rsv);

        // 8. RiskEngine（构造需池地址，故在池之后部署）
        RiskEngine re = new RiskEngine(address(oracle), address(pool));
        re.grantRole(re.PARAM_ADMIN_ROLE(), testnetAdmin);

        // 9. init
        rsv.setLendingPool(address(pool));
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), testnetAdmin);
        pool.grantRole(pool.PAUSER_ROLE(), testnetAdmin);
        rsv.transferOwnership(testnetAdmin);

        vm.stopBroadcast();

        //
        console2.log("=== ZZZ Lend Sepolia      ===");
        console2.log("Deployer:       ", deployer);
        console2.log("TestnetAdmin:   ", testnetAdmin);
        console2.log("MockUSDC:       ", address(usdc));
        console2.log("ChainlinkOracle:", address(oracle));
        console2.log("SwitchableOracle:", address(switchable));
        console2.log("MockPriceOracle:", address(mockOracle));
        console2.log("InterestRateModel:", address(irm));
        console2.log("RiskManager:    ", address(rm));
        console2.log("LiquidationManager:", address(lm));
        console2.log("ReserveManager: ", address(rsv));
        console2.log("RiskEngine:     ", address(re));
        console2.log("LendingPool:    ", address(pool));
        console2.log("ETH/USD Feed:   ", ethUsdFeed);
        console2.log("USDC/USD Feed:  ", usdcUsdFeed);

        //    deployments/sepolia.json   E2E/
        string memory obj;
        obj = vm.serializeUint("root", "chainId", block.chainid);
        obj = vm.serializeAddress("root", "usdc", address(usdc));
        obj = vm.serializeAddress("root", "oracle", address(oracle));
        obj = vm.serializeAddress("root", "switchableOracle", address(switchable));
        obj = vm.serializeAddress("root", "mockOracle", address(mockOracle));
        obj = vm.serializeAddress("root", "interestRateModel", address(irm));
        obj = vm.serializeAddress("root", "riskManager", address(rm));
        obj = vm.serializeAddress("root", "liquidationManager", address(lm));
        obj = vm.serializeAddress("root", "reserveManager", address(rsv));
        obj = vm.serializeAddress("root", "riskEngine", address(re));
        obj = vm.serializeAddress("root", "lendingPool", address(pool));
        obj = vm.serializeAddress("root", "testnetAdmin", testnetAdmin);
        obj = vm.serializeString("root", "ethUsdFeed", vm.toString(ethUsdFeed));
        obj = vm.serializeString("root", "usdcUsdFeed", vm.toString(usdcUsdFeed));
        vm.writeJson(obj, "./deployments/sepolia.json");

        console2.log("");
        console2.log("===     ===");
        console2.log("1) verify: script/Verify.s.sol   see docs/ZZZ_Lend master doc");
        console2.log(
            "2) e2e: forge script script/TestnetE2E.s.sol:TestnetE2E --rpc-url $SEPOLIA_RPC_URL --broadcast -vvvv"
        );
        console2.log("3) cast manual: see docs/ZZZ_Lend master doc section 6");
    }
}
