// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Test} from "forge-std/Test.sol";
import {MockPriceOracle} from "../src/mocks/MockPriceOracle.sol";
import {InterestRateModel} from "../src/InterestRateModel.sol";
import {RiskManager} from "../src/RiskManager.sol";
import {LiquidationManager} from "../src/LiquidationManager.sol";
import {ReserveManager} from "../src/ReserveManager.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";

/// @notice 在每次代币转账时尝试重入 pool.withdraw，验证 ReentrancyGuard。
contract ReentrantToken is MockUSDC {
    LendingPool public attackPool;
    bool public attack;

    function setAttack(address poolAddr, bool _attack) external {
        attackPool = LendingPool(poolAddr);
        attack = _attack;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (attack && address(attackPool) != address(0)) {
            attackPool.withdraw(1);
        }
    }
}

contract SecurityTest is Test {
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    ReentrantToken internal token;
    MockPriceOracle internal oracle;
    LendingPool internal pool;
    address internal supplier;
    address internal borrower;
    address internal liquidator;

    function _deployStack() internal {
        supplier = makeAddr("supplier");
        borrower = makeAddr("borrower");
        liquidator = makeAddr("liquidator");
        token = new ReentrantToken();
        oracle = new MockPriceOracle();
        oracle.setPrice(ETH, 3000e8);
        oracle.setPrice(address(token), 1e8);
        InterestRateModel irm = new InterestRateModel();
        RiskManager rm = new RiskManager();
        LiquidationManager lm = new LiquidationManager();
        ReserveManager rsv = new ReserveManager(address(token));
        pool = new LendingPool(token, oracle, irm, rm, lm, rsv);
        rsv.setLendingPool(address(pool));
        vm.deal(supplier, 1 ether);
        vm.deal(borrower, 1 ether);
        vm.deal(liquidator, 1 ether);
        token.faucet(3_000_000e6);
        token.transfer(supplier, 1_000_000e6);
        token.transfer(borrower, 1_000_000e6);
        token.transfer(liquidator, 1_000_000e6);
    }

    function test_ReentrancyOnBorrowBlocked() public {
        _deployStack();
        vm.prank(supplier);
        token.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(100_000e6);
        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();

        vm.prank(borrower);
        token.setAttack(address(pool), true);

        vm.prank(borrower);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        pool.borrow(100e6, 1);
    }

    function test_ReentrancyOnWithdrawBlocked() public {
        _deployStack();
        vm.prank(supplier);
        token.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(1000e6);

        vm.prank(supplier);
        token.setAttack(address(pool), true);

        vm.prank(supplier);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        pool.withdraw(1000e6);
    }

    function test_ReentrancyOnLiquidationBlocked() public {
        _deployStack();
        vm.prank(supplier);
        token.approve(address(pool), type(uint256).max);
        vm.prank(supplier);
        pool.supply(100_000e6);
        vm.prank(borrower);
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(borrower);
        pool.borrow(2000e6, 5);

        oracle.setPrice(ETH, 2000e8); // HF = 0.9, 可清算

        vm.prank(liquidator);
        token.approve(address(pool), type(uint256).max);
        vm.prank(liquidator);
        token.setAttack(address(pool), true);

        vm.prank(liquidator);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        pool.liquidate(borrower, 500e6, 0);
    }
}
