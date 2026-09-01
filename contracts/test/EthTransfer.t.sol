// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {BaseSetup} from "./BaseSetup.t.sol";

/// @notice 只收 ETH，不重入的合约。
contract EthReceiver {
    receive() external payable {}
}

/// @notice 收到 ETH 时尝试重入 pool.withdraw 的恶意合约。
contract ReentrantEthReceiver {
    LendingPool public pool;
    uint256 public shares;
    bool public attack;

    function set(LendingPool p, uint256 s, bool a) external {
        pool = p;
        shares = s;
        attack = a;
    }

    receive() external payable {
        if (attack && shares > 0) {
            pool.withdraw(shares);
        }
    }
}

contract EthTransferTest is BaseSetup {
    function test_ContractRecipientReceivesCollateral() public {
        EthReceiver rec = new EthReceiver();
        vm.deal(address(rec), 1 ether);
        vm.prank(address(rec));
        pool.supplyCollateral{value: 1 ether}();
        uint256 before = address(rec).balance;
        vm.prank(address(rec));
        pool.withdrawCollateral(0.5 ether);
        assertEq(address(rec).balance, before + 0.5 ether);
        assertEq(pool.getCollateralValue(address(rec)) > 0 ? 1 : 0, 1); // 仍有余抵押
    }

    function test_LiquidationSendsEthToContractRecipient() public {
        EthReceiver liq = new EthReceiver();
        vm.deal(address(liq), 1 ether);
        usdc.transfer(address(liq), 10_000e6);
        _supply(bob, 10_000e6);
        _supplyCollateral(alice, 1 ether);
        _borrow(alice, 2000e6, 5);
        oracle.setPrice(ETH, 2000e8); // HF=0.9 可清算
        uint256 before = address(liq).balance;
        vm.prank(address(liq));
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(address(liq));
        pool.liquidate(alice, 1000e6, 0);
        assertGt(address(liq).balance, before); // ETH 到账，未因 2300 gas 失败
    }

    function test_ReentrancyStillBlockedByGuard() public {
        ReentrantEthReceiver rec = new ReentrantEthReceiver();
        usdc.transfer(address(rec), 1000e6);
        vm.deal(address(rec), 2 ether);
        vm.prank(address(rec));
        usdc.approve(address(pool), type(uint256).max);
        vm.prank(address(rec));
        pool.supply(1000e6);
        vm.prank(address(rec));
        pool.supplyCollateral{value: 1 ether}();
        vm.prank(address(rec));
        rec.set(pool, 1000e6, true);
        // 取抵押时 ETH call 触发 receive() 重入 withdraw，被 ReentrancyGuard 拦截 → 外层 revert
        vm.prank(address(rec));
        vm.expectRevert(bytes("eth transfer failed"));
        pool.withdrawCollateral(0.5 ether);
    }
}
