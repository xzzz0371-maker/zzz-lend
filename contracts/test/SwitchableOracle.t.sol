// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {SwitchableOracle} from "../src/oracle/SwitchableOracle.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";

contract SwitchableOracleTest is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    SwitchableOracle internal oracle;
    MockPriceOracle internal primary;
    address internal admin;
    address internal pauser;
    address internal alice;

    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        alice = makeAddr("alice");
        primary = new MockPriceOracle();
        primary.setPrice(ETH, 3000e8);
        oracle = new SwitchableOracle(primary);
        oracle.grantRole(oracle.PARAM_ADMIN_ROLE(), admin);
        oracle.grantRole(oracle.PAUSER_ROLE(), pauser);
    }

    function test_DefaultUsesPrimary() public view {
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
        assertEq(oracle.useSettablePrice(), false);
    }

    function test_SwitchToSettableMode() public {
        vm.prank(pauser);
        oracle.enableSettable();
        assertTrue(oracle.useSettablePrice());
        // 未设价时 revert
        vm.expectRevert(bytes("price not set"));
        oracle.getAssetPrice(ETH);
        // 管理员设价
        vm.prank(admin);
        oracle.setPrice(ETH, 2100e8); // -30%
        assertEq(oracle.getAssetPrice(ETH), 2100e8);
    }

    function test_DisableSettableBackToPrimary() public {
        vm.prank(pauser);
        oracle.enableSettable();
        vm.prank(admin);
        oracle.setPrice(ETH, 2100e8);
        vm.prank(pauser);
        oracle.disableSettable();
        assertFalse(oracle.useSettablePrice());
        assertEq(oracle.getAssetPrice(ETH), 3000e8); // 回到主源
    }

    function test_OnlyPauserCanSwitchMode() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, oracle.PAUSER_ROLE()
            )
        );
        vm.prank(alice);
        oracle.enableSettable();
        vm.prank(pauser);
        oracle.enableSettable();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, oracle.PAUSER_ROLE()
            )
        );
        vm.prank(alice);
        oracle.disableSettable();
    }

    function test_OnlyParamAdminCanSetPrice() public {
        vm.prank(pauser);
        oracle.enableSettable();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, alice, oracle.PARAM_ADMIN_ROLE()
            )
        );
        vm.prank(alice);
        oracle.setPrice(ETH, 1e8);
    }

    function test_PauseBlocksRead() public {
        vm.prank(pauser);
        oracle.pause();
        vm.expectRevert(bytes("oracle paused"));
        oracle.getAssetPrice(ETH);
        vm.prank(pauser);
        oracle.unpause();
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
    }

    function test_IntegrationLiquidationViaSettableMode() public {
        // 用 SwitchableOracle 作为 LendingPool 价格源，完整跑清算
        MockUSDC usdc = new MockUSDC();
        primary.setPrice(address(usdc), 1e8); // USDC = 1 USD
        InterestRateModel irm = new InterestRateModel();
        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(address(usdc));
        LendingPool pool = new LendingPool(usdc, oracle, irm, rm, lm, rsv);
        rsv.setLendingPool(address(pool));
        pool.grantRole(pool.PARAM_ADMIN_ROLE(), admin);
        pool.grantRole(pool.PAUSER_ROLE(), admin);

        address supplier = makeAddr("supplier");
        address borrower = makeAddr("borrower");
        address liquidator = makeAddr("liquidator");
        vm.deal(borrower, 1 ether);
        vm.deal(liquidator, 1 ether);
        usdc.faucet(200_000e6);
        usdc.transfer(supplier, 100_000e6);
        usdc.transfer(liquidator, 100_000e6);

        vm.prank(supplier);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(0, 100_000e6);

        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}(); // 3000 USD @ primary
        vm.prank(borrower);
        pool.borrow(0, 2000e6, 5); // LTV 66.7%
        assertGt(pool.getUserHealthFactor(borrower), 1e18);

        // PAUSER 切换到可设价模式，管理员设 ETH 价 -50% (1500) 及 USDC=1
        vm.prank(pauser);
        oracle.enableSettable();
        vm.prank(admin);
        oracle.setPrice(ETH, 1500e8);
        vm.prank(admin);
        oracle.setPrice(address(usdc), 1e8); // 可设价模式下需为所有用到的资产设价
        assertLt(pool.getUserHealthFactor(borrower), 1e18);
        assertTrue(pool.isLiquidatable(borrower));

        vm.prank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        pool.liquidate(borrower, 0, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, 2000e6, 0);
        assertLt(pool.getDebt(borrower), 2000e6 * 1e12);

        // 切回主源
        vm.prank(pauser);
        oracle.disableSettable();
        assertEq(oracle.getAssetPrice(ETH), 3000e8);
        // 资金守恒
        assertApproxEqAbs(
            pool.cash() + pool.getTotalBorrows(),
            pool.getTotalSupply() + pool.totalReserve() + pool.treasuryAccrued(),
            1e7
        );
    }
}
