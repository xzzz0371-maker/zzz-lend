// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ChainlinkOracle} from "../src/oracle/ChainlinkOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {RiskEngine} from "../src/risk/RiskEngine.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @title 主网权限收口流程（分步，可在已部署栈上单独执行 Step 4–11）
/// @dev
///   ⚠️ 本脚本**不做合约部署**（部署请先跑 DeployMainnet.s.sol 得到 deployments/mainnet.json）。
///   本脚本只做“权限收口”：把 PARAM_ADMIN/DEFAULT_ADMIN/Ownable 移交到 Safe(或 Timelock)，撤销部署者。
///
///   分步（对应手册 §4）：
///     Step 4/5:  设置 treasuryAddress=SAFE；PAUSER → SAFE
///     Step 6/7:  pool/oracle/riskEngine DEFAULT_ADMIN + PARAM_ADMIN → TIMELOCK（未启用 timelock 则 → SAFE）
///     Step 8:    IRM/RiskManager/ReserveManager transferOwnership(TIMELOCK 或 SAFE)
///     Step 9:    部署者逐个 renounceRole / 移交后撤销
///     Step 10/11: 只读断言脚本输出，需链上再手动验证
///
///   用法（先填 .env）：
///     forge script script/MainnetDeployAndTransfer.s.sol:MainnetDeployAndTransfer \
///           --rpc-url $MAINNET_RPC_URL --broadcast -vvvv
///   环境变量：
///     PRIVATE_KEY                    部署者（将被撤销）
///     MAINNET_DEPLOYMENTS            （可选）已部署 json 路径，默认 ./deployments/mainnet.json
///     MAINNET_ADMIN_SAFE             Safe 多签地址（必填，最终持有方）
///     MAINNET_TREASURY               （可选，默认=SAFE）
///     MAINNET_TIMELOCK               （可选）已部署 TimelockController 地址；不设则 governance=SAFE
///     MAINNET_PAUSER                 （可选，默认=SAFE）——若你希望 pauser 与 owner 分离，可传另一多签
///
///   ⚠️ 流程骨架以“步骤清晰、可审计”为要；请先在本机 fork 预演，确认步骤顺序与预期一致再真网广播。
contract MainnetDeployAndTransfer is Script {
    // 步骤标记，仅供注释清晰。

    /// @notice 读取 env address，未设置则返回默认。
    function _envAddrOr(string memory key, address dflt) internal view returns (address) {
        try vm.envAddress(key) returns (address v) {
            return v;
        } catch {
            return dflt;
        }
    }

    function _envStrOr(string memory key, string memory dflt) internal view returns (string memory) {
        try vm.envString(key) returns (string memory v) {
            return v;
        } catch {
            return dflt;
        }
    }

    function run() external {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(key);
        address safe = vm.envAddress("MAINNET_ADMIN_SAFE");
        address treasury = _envAddrOr("MAINNET_TREASURY", safe);
        address pauser = _envAddrOr("MAINNET_PAUSER", safe);
        address payable timelockAddr = payable(_envAddrOr("MAINNET_TIMELOCK", address(0)));
        address governance = timelockAddr == address(0) ? safe : address(timelockAddr);

        string memory cfg = vm.readFile(_envStrOr("MAINNET_DEPLOYMENTS", "./deployments/mainnet.json"));
        LendingPool pool = LendingPool(vm.parseJsonAddress(cfg, ".lendingPool"));
        ChainlinkOracle oracle = ChainlinkOracle(vm.parseJsonAddress(cfg, ".oracle"));
        InterestRateModel irm = InterestRateModel(vm.parseJsonAddress(cfg, ".interestRateModel"));
        RiskManager rm = RiskManager(vm.parseJsonAddress(cfg, ".riskManager"));
        ReserveManager rsv = ReserveManager(vm.parseJsonAddress(cfg, ".reserveManager"));
        RiskEngine re = RiskEngine(vm.parseJsonAddress(cfg, ".riskEngine"));

        console2.log("deployer:", deployer);
        console2.log("safe:", safe);
        console2.log("treasury:", treasury);
        console2.log("pauser:", pauser);
        console2.log("timelock:", address(timelockAddr), "-> governance:", governance);
        vm.startBroadcast(key);

        // ===== Step 4: treasuryAddress = treasury =====
        pool.setTreasuryAddress(treasury);

        // ===== Step 5: PAUSER → pauser（独立熔断，不经 timelock）=====
        pool.grantRole(pool.PAUSER_ROLE(), pauser);
        oracle.grantRole(oracle.PAUSER_ROLE(), pauser);

        // ===== Step 6/7: DEFAULT_ADMIN + PARAM_ADMIN → governance =====
        pool.grantRole(pool.DEFAULT_ADMIN_ROLE(), governance);
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), governance);
        oracle.grantRole(oracle.DEFAULT_ADMIN_ROLE(), governance);
        oracle.grantRole(oracle.PARAM_ADMIN_ROLE(), governance);
        re.grantRole(re.DEFAULT_ADMIN_ROLE(), governance);
        re.grantRole(re.PARAM_ADMIN_ROLE(), governance);

        // ===== Step 8: Ownable → governance =====
        irm.transferOwnership(governance);
        rm.transferOwnership(governance);
        rsv.transferOwnership(governance);

        // ===== Step 9: 撤销部署者（先子角色，最后 DEFAULT_ADMIN）=====
        pool.renounceRole(pool.PARAM_ADMIN_ROLE(), deployer);
        pool.renounceRole(pool.PAUSER_ROLE(), deployer);
        pool.renounceRole(pool.DEFAULT_ADMIN_ROLE(), deployer);
        oracle.renounceRole(oracle.PARAM_ADMIN_ROLE(), deployer);
        oracle.renounceRole(oracle.PAUSER_ROLE(), deployer);
        oracle.renounceRole(oracle.DEFAULT_ADMIN_ROLE(), deployer);
        re.renounceRole(re.PARAM_ADMIN_ROLE(), deployer);
        re.renounceRole(re.DEFAULT_ADMIN_ROLE(), deployer);

        vm.stopBroadcast();

        // ===== Step 10/11: 只读输出供人工链上复核 =====
        console2.log("pool DEFAULT_ADMIN(gov):", pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), governance));
        console2.log("pool PARAM_ADMIN(gov):", pool.hasRole(pool.PARAM_ADMIN_ROLE(), governance));
        console2.log("pool PAUSER(safe):", pool.hasRole(pool.PAUSER_ROLE(), pauser));
        console2.log("deployer revoked (pool DEFAULT):", !pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), deployer));
        console2.log("irm owner==governance:", irm.owner() == governance);
        console2.log("riskManager owner==governance:", rm.owner() == governance);
        console2.log("reserveManager owner==governance:", rsv.owner() == governance);
        console2.log("treasuryAddress:", pool.treasuryAddress());
        if (timelockAddr != address(0)) {
            TimelockController tl = TimelockController(payable(timelockAddr));
            console2.log("timelock PROPOSER(safe):", tl.hasRole(tl.PROPOSER_ROLE(), safe));
            console2.log("timelock EXECUTOR(safe):", tl.hasRole(tl.EXECUTOR_ROLE(), safe));
        }
        console2.log(
            "NOTE: manually verify Step10/11 on chain (deployer calls rejected, pauser can pause instantly, param changes go through timelock)."
        );
    }
}
