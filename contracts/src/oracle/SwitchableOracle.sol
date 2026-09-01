// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @notice 可切换预言机（OracleWrapper）。
/// 主源 = 真实 Chainlink；测试时 PAUSER 可切换到"管理员可设价"模式，演示/压力结束后由 PAUSER 切回主源。
/// 实现 IPriceOracle，可无缝作为 LendingPool 的价格源。
contract SwitchableOracle is AccessControl, IPriceOracle {
    bytes32 public constant PARAM_ADMIN_ROLE = keccak256("PARAM_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IPriceOracle public primaryOracle; // 真实 Chainlink（正常模式）
    mapping(address => uint256) public settablePrice; // 管理员可设价（测试模式）
    bool public useSettablePrice; // false=主源; true=可设价模式
    bool public paused;

    event PrimaryOracleSet(address indexed oracle);
    event PriceSet(address indexed asset, uint256 price);
    event SettableMode(bool state);
    event OracleSwitched(bool useSettablePrice);
    event Paused(bool state);

    constructor(IPriceOracle primary_) {
        require(address(primary_) != address(0), "zero primary");
        primaryOracle = primary_;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PARAM_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ==================== PARAM_ADMIN ====================

    function setPrimaryOracle(IPriceOracle oracle) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(oracle) != address(0), "zero address");
        primaryOracle = oracle;
        emit PrimaryOracleSet(address(oracle));
    }

    /// @notice 管理员设价（仅 PARAM_ADMIN）。在可设价模式下生效。
    /// 价格必须 > 0 且在 [1e2, 1e14]（8 位小数，即 $1e-6 ~ $1e6），防止误设 0 或任意极大值（F3）。
    function setPrice(address asset, uint256 price) external onlyRole(PARAM_ADMIN_ROLE) {
        require(asset != address(0), "zero asset");
        require(price > 0, "price must be > 0");
        require(price >= 1e2 && price <= 1e14, "price out of range");
        settablePrice[asset] = price;
        emit PriceSet(asset, price);
    }

    // ==================== PAUSER ====================

    /// @notice 切换到可设价模式（测试/应急用）。
    function enableSettable() external onlyRole(PAUSER_ROLE) {
        useSettablePrice = true;
        emit SettableMode(true);
        emit OracleSwitched(true);
    }

    /// @notice 切回主源（真实 Chainlink）。清算测试结束后必须调用。
    function disableSettable() external onlyRole(PAUSER_ROLE) {
        useSettablePrice = false;
        emit SettableMode(false);
        emit OracleSwitched(false);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(true);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Paused(false);
    }

    // ==================== IPriceOracle ====================

    function getAssetPrice(address asset) external view returns (uint256) {
        require(!paused, "oracle paused");
        if (useSettablePrice) {
            uint256 p = settablePrice[asset];
            require(p > 0, "price not set");
            return p;
        }
        return primaryOracle.getAssetPrice(asset);
    }

    /// @notice 主源模式下透传主源的异常状态；可设价模式（测试）视为正常。
    function isPriceAnomalous(address asset) external view returns (bool) {
        if (useSettablePrice) return false;
        return primaryOracle.isPriceAnomalous(asset);
    }
}
