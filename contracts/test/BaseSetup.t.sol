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

abstract contract BaseSetup is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant WAD = 1e18;

    MockUSDC internal usdc;
    MockPriceOracle internal oracle;
    InterestRateModel internal irm;
    RiskManager internal riskManager;
    LiquidationManager internal liquidationManager;
    ReserveManager internal reserveManager;
    LendingPool internal pool;

    address internal admin;
    address internal alice;
    address internal bob;
    address internal liquidator;

    function setUp() public virtual {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        liquidator = makeAddr("liquidator");

        vm.deal(alice, 1000 ether);
        vm.deal(bob, 1000 ether);
        vm.deal(liquidator, 1000 ether);

        usdc = new MockUSDC();
        oracle = new MockPriceOracle();
        oracle.setPrice(ETH, 3000e8);
        oracle.setPrice(address(usdc), 1e8);

        irm = new InterestRateModel();
        riskManager = new RiskManager();
        liquidationManager = new LiquidationManager();
        reserveManager = new ReserveManager(address(usdc));

        pool = new LendingPool(usdc, oracle, irm, riskManager, liquidationManager, reserveManager);
        reserveManager.setLendingPool(address(pool));

        pool.grantRole(pool.PARAM_ADMIN_ROLE(), admin);
        pool.grantRole(pool.PAUSER_ROLE(), admin);

        irm.setMarketGovernor(admin);

        usdc.faucet(10_000_000e6);
        usdc.transfer(alice, 500_000e6);
        usdc.transfer(bob, 500_000e6);
        usdc.transfer(liquidator, 500_000e6);
    }

    function _approveUsdc(address who, uint256 amount) internal {
        vm.prank(who);
        usdc.approve(address(pool), amount);
    }

    function _supply(address who, uint256 amount) internal {
        _approveUsdc(who, amount);
        vm.prank(who);
        pool.supply(amount);
    }

    function _supplyCollateral(address who, uint256 ethAmount) internal {
        vm.prank(who);
        pool.supplyCollateral{value: ethAmount}();
    }

    function _borrow(address who, uint256 amount, uint256 tier) internal {
        vm.prank(who);
        pool.borrow(amount, tier);
    }
}
