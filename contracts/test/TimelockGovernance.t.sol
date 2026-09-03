// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {BaseSetup} from "./BaseSetup.t.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";

/// @notice 治理 Timelock：模拟主网部署——多签(admin)不再直持 PARAM_ADMIN，而是经 OZ TimelockController：
///         - 参数变更（pool/IRM/…）必须由 admin 以 PROPOSER 身份 schedule，延时后由 executor 执行；
///         - 在延时内不可执行；执行后变更生效；
///         - PAUSER 独立于 timelock（快速熔断不被延迟）；
///         - 部署者撤销全部角色后不可再直接改参数。
/// 本测试基于新部署栈（不改动 DeployMainnet 的链上执行，仅验证其“governance=timelock”的语义）。
contract TimelockGovernanceTest is BaseSetup {
    TimelockController internal timelock;
    uint256 internal constant MIN_DELAY = 2 days;

    event CallScheduled(
        bytes32 indexed id,
        uint256 indexed index,
        address target,
        uint256 value,
        bytes data,
        bytes32 predecessor,
        uint256 delay
    );
    event CallExecuted(bytes32 indexed id, uint256 indexed index, address target, uint256 value, bytes data);

    function setUp() public override {
        BaseSetup.setUp(); // deployer(msg.sender) = 本测试合约；admin/alice 等为普通地址
    }

    /// @notice 构造 timelock，并把 pool 的 PARAM_ADMIN 与 IRM/池角色移交，模拟主网治理结构。
    function _deployGovernedStack() internal {
        address[] memory proposers = new address[](1);
        proposers[0] = admin; // 多签
        address[] memory executors = new address[](1);
        executors[0] = admin; // 多签可执行
        timelock = new TimelockController(MIN_DELAY, proposers, executors, address(0));

        // BaseSetup 已把 PARAM_ADMIN 授给 admin（仅测试基座）。治理模式下撤销 admin 的 PARAM_ADMIN：
        // 只保留 PAUSER（快速熔断）。PARAM_ADMIN/DEFAULT_ADMIN → timelock。
        pool.revokeRole(pool.PARAM_ADMIN_ROLE(), admin);
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), address(timelock));
        pool.grantRole(pool.PAUSER_ROLE(), admin);
        pool.grantRole(pool.DEFAULT_ADMIN_ROLE(), address(timelock));
        pool.renounceRole(pool.PARAM_ADMIN_ROLE(), address(this));
        pool.renounceRole(pool.PAUSER_ROLE(), address(this));
        pool.renounceRole(pool.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function _scheduleSetReserveTarget(uint256 newTarget) internal returns (bytes32 id) {
        bytes memory data = abi.encodeCall(LendingPool.setReserveTargetRatio, (newTarget));
        id = timelock.hashOperation(address(pool), 0, data, bytes32(0), bytes32(0));
        vm.prank(admin); // proposer
        timelock.schedule(address(pool), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
    }

    function test_ParamChangeRequiresTimelockDelay() public {
        _deployGovernedStack();
        // 直接调用（多签/任何人）→ 已被拒（PARAM_ADMIN 只在 timelock 上）
        vm.prank(admin);
        vm.expectRevert();
        pool.setReserveTargetRatio(5e16);

        bytes32 id = _scheduleSetReserveTarget(5e16);

        // 延时未过 → 不可执行
        vm.warp(block.timestamp + MIN_DELAY - 1);
        vm.prank(admin);
        vm.expectRevert();
        timelock.execute(
            address(pool), 0, abi.encodeCall(LendingPool.setReserveTargetRatio, (5e16)), bytes32(0), bytes32(0)
        );
        assertEq(pool.reserveTargetRatio(), 3e16); // 未变

        // 延时过后 → 执行成功
        vm.warp(block.timestamp + 2);
        vm.prank(admin);
        timelock.execute(
            address(pool), 0, abi.encodeCall(LendingPool.setReserveTargetRatio, (5e16)), bytes32(0), bytes32(0)
        );
        assertEq(pool.reserveTargetRatio(), 5e16);
    }

    function test_PauserIndependentOfTimelock() public {
        _deployGovernedStack();
        // PAUSER=admin 可即时 pause（不经过 timelock 延迟）
        vm.prank(admin);
        pool.pause();
        assertTrue(pool.paused());
        vm.prank(admin);
        pool.unpause();
        assertFalse(pool.paused());
    }

    function test_DeployerCannotBypassAfterRenounce() public {
        _deployGovernedStack();
        // 部署者（本测试合约）已 renounce PARAM/PAUSER/DEFAULT → 直接改参被拒
        vm.expectRevert();
        pool.setReserveFactor(6e16);
        vm.expectRevert();
        pool.pause();
    }

    function test_TimelockCanChangeIrmPresetOnlyGoverned() public {
        _deployGovernedStack();
        // 未授权直改 IRM preset（IRM owner 仍是部署者？默认 owner=msg.sender→本测试）
        // 主网部署时 IRM ownership 会 transferOwnership(governance)；这里仅验证走 timelock 的 IRM 路径：
        // 把 IRM 的所有权也移到 timelock 后再由 timelock 执行 setParams（仅示例 schedule/execute 泛化）。
        irm.transferOwnership(address(timelock));
        bytes memory data = abi.encodeCall(InterestRateModel.setSlope2a, (uint256(0.3e18)));
        bytes32 id = timelock.hashOperation(address(irm), 0, data, bytes32(0), bytes32(0));
        vm.prank(admin);
        timelock.schedule(address(irm), 0, data, bytes32(0), bytes32(0), MIN_DELAY);
        vm.warp(block.timestamp + MIN_DELAY + 1);
        vm.prank(admin);
        timelock.execute(address(irm), 0, data, bytes32(0), bytes32(0));
        assertGt(irm.slope2aPerSecond(), 0);
        emit log_named_uint("slope2a executed ok", irm.slope2aPerSecond());
        // 部署者/任意人不能再直改（owner=timelock）
        vm.expectRevert();
        irm.setSlope2a(uint256(0.2e18));
    }
}
