// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {BaseSetup} from "./BaseSetup.t.sol";

/// @notice Early Deposit Boost 测试：Tier1+2 利息保底到 2% APY（前 6 个月，每钱包 1 万 USDC，只补利息）。
contract BoostTest is BaseSetup {
    event BoostClaimed(address indexed user, uint256 amount);

    address internal carol;

    function setUp() public override {
        super.setUp();
        carol = makeAddr("carol");
        vm.deal(carol, 200 ether);
    }

    function _assertInvariant() internal view {
        uint256 lhs = pool.cash() + pool.getTotalBorrows();
        uint256 rhs = pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued() + pool.boostPool();
        assertTrue(lhs >= rhs ? (lhs - rhs) <= 1e6 : (rhs - lhs) <= 1e6, "invariant broken");
    }

    function _setBoostWindow() internal {
        vm.prank(admin);
        pool.setBoostParams(block.timestamp, block.timestamp + 180 days, 2e16, 10_000e6);
    }

    function _fundBoost(uint256 amount) internal {
        usdc.faucet(amount); // 测试合约铸币并作为 PARAM_ADMIN 注入保底基金
        usdc.approve(address(pool), type(uint256).max);
        pool.fundBoost(amount);
    }

    function _full2Pct(uint256 eligible, uint256 dt) internal pure returns (uint256) {
        return eligible * 2e16 * dt / (1e18 * 31536000);
    }

    /// @dev 利用率 0%：无借款 → 无 Tier1+2 利息 → 全额 2% 保底。
    function test_Boost_ZeroUtilizationPaysFull2Pct() public {
        _supply(alice, 10_000e6);
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        _fundBoost(10_000e6);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(bob); // 任何人可为 alice 领取
        pool.claimBoost(alice);
        uint256 gained = usdc.balanceOf(alice) - balBefore;
        assertApproxEqAbs(gained, _full2Pct(10_000e6, 30 days), 1e6);
        (uint256 eligible, uint256 claimed, uint256 remaining,, uint256 timeLeft) = pool.getBoostStatus(alice);
        assertEq(eligible, 10_000e6);
        assertApproxEqAbs(claimed, gained, 1);
        assertApproxEqAbs(remaining, 10_000e6 - gained, 1e6);
        assertGt(timeLeft, 0);
        _assertInvariant();
    }

    /// @dev 利用率 10%（Tier1 借款）：Tier1+2 利息抵扣保底。
    function test_Boost_Util10PctTier1InterestOffset() public {
        _supply(alice, 10_000e6);
        _supply(bob, 90_000e6);
        _supplyCollateral(carol, 30 ether); // 90,000 USD
        _borrow(carol, 10_000e6, 1); // util = 10%
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        _fundBoost(10_000e6);

        (uint256 aliceShares,,,,,,) = pool.getUserPosition(alice);
        uint256 totalShares = pool.totalShares();
        uint256 actual = pool.tier12Interest() * pool.depositorShare() / 1e18 * aliceShares / totalShares;
        uint256 guaranteed = _full2Pct(10_000e6, 30 days);
        uint256 expected = guaranteed > actual ? guaranteed - actual : 0;
        assertGt(pool.tier12Interest(), 0);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(bob);
        pool.claimBoost(alice);
        uint256 gained = usdc.balanceOf(alice) - balBefore;
        assertApproxEqAbs(gained, expected, 2e6);
        assertLt(gained, guaranteed); // 被 Tier1 利息抵扣后少于全额保底
        _assertInvariant();
    }

    /// @dev 高利用率（~99%，Tier1 借款）：新利率下档息足够 → 无保底可领。
    ///     注：新 NORMAL 曲线（base 0.5/slope1 4）下，Tier1 借款在 ≤80% 利用率时存款人分摊 < 2%，
    ///     故用近 100% 利用率构造"Tier1+2 利息已 ≥ 2%"的边界。
    function test_Boost_Util99PctTier1InterestSufficient() public {
        _supply(alice, 10_000e6);
        _supply(bob, 90_000e6);
        _supplyCollateral(carol, 66 ether); // 198,000 USD
        _borrow(carol, 99_000e6, 1); // util ≈ 99%（tier1 上限）
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        _fundBoost(10_000e6);
        assertGt(pool.tier12Interest(), 0);

        vm.prank(bob);
        vm.expectRevert(bytes("nothing to claim"));
        pool.claimBoost(alice);
        _assertInvariant();
    }

    /// @dev 保底上限：超过 1 万 USDC 的部分不享受。
    function test_Boost_CapPerWallet() public {
        _supply(alice, 20_000e6); // 存入 2 万，合格只按 1 万
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        _fundBoost(10_000e6);

        (uint256 eligible,,,,) = pool.getBoostStatus(alice);
        assertEq(eligible, 10_000e6);

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(bob);
        pool.claimBoost(alice);
        uint256 gained = usdc.balanceOf(alice) - balBefore;
        assertApproxEqAbs(gained, _full2Pct(10_000e6, 30 days), 1e6); // 按 1 万，而非 2 万
        _assertInvariant();
    }

    /// @dev 到期后无法再领取。
    function test_Boost_ExpiryBlocksClaim() public {
        _supply(alice, 10_000e6);
        _setBoostWindow();
        vm.warp(block.timestamp + 181 days);
        pool.accrue();
        _fundBoost(10_000e6);

        vm.prank(alice);
        vm.expectRevert(bytes("boost ended"));
        pool.claimBoost(alice);
    }

    /// @dev 到期后 getBoostStatus 剩余期限为 0。
    function test_Boost_StatusTimeLeftAfterEnd() public {
        _supply(alice, 10_000e6);
        _setBoostWindow();
        vm.warp(block.timestamp + 181 days);
        (,,,, uint256 timeLeft) = pool.getBoostStatus(alice);
        assertEq(timeLeft, 0);
    }

    /// @dev Tier3/4/5 借款利息不参与保底核算：即使有高息借款，仍按 Tier1+2 空口全额保底。
    function test_Boost_Tier345InterestDoesNotCount() public {
        _supply(alice, 10_000e6);
        _supply(bob, 90_000e6);
        _supplyCollateral(carol, 100 ether);
        _borrow(carol, 50_000e6, 5); // 高息借款（tier5）
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + 1);
        pool.accrue();
        _fundBoost(10_000e6);
        assertEq(pool.tier12Interest(), 0); // Tier1+2 无利息
        assertGt(pool.tier345Interest(), 0); // 利息全在 Tier3/4/5

        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(bob);
        pool.claimBoost(alice);
        uint256 gained = usdc.balanceOf(alice) - balBefore;
        assertApproxEqAbs(gained, _full2Pct(10_000e6, 30 days), 1e6); // 全额保底，高息档不抵扣
        _assertInvariant();
    }

    /// @dev 设置参数只有 PARAM_ADMIN 可调。
    function test_Boost_OnlyParamAdminCanSetParams() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, pool.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        pool.setBoostParams(block.timestamp, block.timestamp + 180 days, 2e16, 10_000e6);
    }

    /// @dev 未开始 / 未配置时领取 revert。
    function test_Boost_BeforeStartReverts() public {
        _supply(alice, 10_000e6);
        vm.prank(admin);
        pool.setBoostParams(block.timestamp + 10 days, block.timestamp + 200 days, 2e16, 10_000e6);
        _fundBoost(10_000e6);
        vm.prank(alice);
        vm.expectRevert(bytes("boost not started"));
        pool.claimBoost(alice);
    }

    /// @dev 连续领取：第一次后立即领取无新时间 → nothing to claim；再经过一段时间可再领。
    function test_Boost_MultipleClaimsAccrue() public {
        _supply(alice, 10_000e6);
        _setBoostWindow();
        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        _fundBoost(10_000e6);

        vm.prank(alice);
        pool.claimBoost(alice);
        vm.prank(alice);
        vm.expectRevert(bytes("nothing to claim"));
        pool.claimBoost(alice); // 同刻无新增

        vm.warp(block.timestamp + 30 days);
        pool.accrue();
        uint256 balBefore = usdc.balanceOf(alice);
        vm.prank(alice);
        pool.claimBoost(alice);
        uint256 second = usdc.balanceOf(alice) - balBefore;
        assertApproxEqAbs(second, _full2Pct(10_000e6, 30 days), 1e6);
        _assertInvariant();
    }
}
