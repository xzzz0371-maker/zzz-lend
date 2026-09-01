// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

/// @title
/// @dev                  forge verify-contract
///   forge script script/Verify.s.sol:Verify --rpc-url $SEPOLIA_RPC_URL
///      ./deployments/sepolia.json   $ETHERSCAN_API_KEY
contract Verify is Script {
    string[] internal names;
    string[] internal paths;

    function run() external {
        string memory cfg = vm.readFile("./deployments/sepolia.json");
        address usdc = vm.parseJsonAddress(cfg, ".usdc");
        address oracle = vm.parseJsonAddress(cfg, ".oracle");
        address switchable = vm.parseJsonAddress(cfg, ".switchableOracle");
        address mockOracle = vm.parseJsonAddress(cfg, ".mockOracle");
        address irm = vm.parseJsonAddress(cfg, ".interestRateModel");
        address rm = vm.parseJsonAddress(cfg, ".riskManager");
        address lm = vm.parseJsonAddress(cfg, ".liquidationManager");
        address rsv = vm.parseJsonAddress(cfg, ".reserveManager");
        address re = vm.parseJsonAddress(cfg, ".riskEngine");
        address pool = vm.parseJsonAddress(cfg, ".lendingPool");

        console2.log("===                ===");
        console2.log("       ETHERSCAN_API_KEY");
        _print("MockUSDC", address(usdc));
        _print("ChainlinkOracle", oracle);
        _print("SwitchableOracle", switchable);
        _print("MockPriceOracle", mockOracle);
        _print("InterestRateModel", irm);
        _print("RiskManager", rm);
        _print("LiquidationManager", lm);
        _print("ReserveManager", rsv);
        _print("RiskEngine", re);
        _print("LendingPool", pool);

        console2.log("");
        console2.log("===      ===");
        console2.log("  A: forge script script/Verify.s.sol:Verify --rpc-url $SEPOLIA_RPC_URL");
        console2.log("  B:              ");
        console2.log("  C:       --verify            ETHERSCAN_API_KEY ");
        console2.log("");
        console2.log("===         ===");
        console2.log("1) Etherscan      Contract source code verified (Solidity), Verified Contract");
        console2.log("2) forge verify-check <  > --chain 11155111 --etherscan-api-key $ETHERSCAN_API_KEY      ");
    }

    function _print(string memory name, address addr) internal view {
        console2.log(
            "forge verify-contract",
            addr,
            name,
            "--chain 11155111 --compiler-version v0.8.24 --etherscan-api-key $ETHERSCAN_API_KEY --watch"
        );
    }
}
