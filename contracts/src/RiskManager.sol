// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRiskManager {
    /// @notice Returns the max LTV for a collateral `token` at a given `tier` (WAD).
    function getMaxLTV(address token, uint256 tier) external view returns (uint256);

    /// @notice Returns the liquidation threshold for a collateral `token` at a given `tier` (WAD).
    function getLiquidationThreshold(address token, uint256 tier) external view returns (uint256);

    function getLiquidationBonus() external view returns (uint256);

    function getCloseFactor() external view returns (uint256);

    function getMaxBorrowTier() external view returns (uint256);
}

/// @notice 风险参数库（V2 多抵押品版）。
/// 每个抵押资产（token）各有一套五档 {maxLTV, liquidationThreshold} 配置；
/// liquidationBonus / closeFactor / maxBorrowTier 保持全局。
/// 为兼容性，ETH 哨兵地址的档位在构造时按 V1 默认值预置；
/// 单 token 的便捷读写（如 getMaxLTV(tier)）绑定 ETH。
contract RiskManager is Ownable, IRiskManager {
    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_TIERS = 5;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    struct TierConfig {
        uint256 maxLTV;
        uint256 liquidationThreshold;
    }

    mapping(address => mapping(uint256 => TierConfig)) public tierConfig;
    uint256 public liquidationBonus = 5e16;
    uint256 public closeFactor = 5e17;
    uint256 public maxBorrowTier = MAX_TIERS;

    event TierUpdated(address indexed token, uint256 tier, uint256 maxLTV, uint256 liquidationThreshold);
    event LiquidationBonusUpdated(uint256 value);
    event CloseFactorUpdated(uint256 value);
    event MaxBorrowTierUpdated(uint256 tier);

    constructor() Ownable(msg.sender) {
        // ETH 默认（与 V1 一致）：50/60/70/75/80 LTV；60/70/78/85/90 LT
        uint256[5] memory ltv = [uint256(5e17), 6e17, 7e17, 75e16, 8e17];
        uint256[5] memory lt = [uint256(6e17), 7e17, 78e16, 85e16, 9e17];
        for (uint256 t = 1; t <= MAX_TIERS; t++) {
            tierConfig[ETH][t] = TierConfig(ltv[t - 1], lt[t - 1]);
        }
    }

    // ==================== Admin (onlyOwner) ====================

    /// @notice 设置某抵押资产的某一档参数。
    function setTier(address token, uint256 tier, uint256 maxLTV, uint256 liquidationThreshold) external onlyOwner {
        _setTier(token, tier, maxLTV, liquidationThreshold);
    }

    /// @notice ETH 便捷入口。
    function setTier(uint256 tier, uint256 maxLTV, uint256 liquidationThreshold) external onlyOwner {
        _setTier(ETH, tier, maxLTV, liquidationThreshold);
    }

    function setLiquidationBonus(uint256 value) external onlyOwner {
        require(value <= 2e17, "bonus>20%");
        liquidationBonus = value;
        emit LiquidationBonusUpdated(value);
    }

    function setCloseFactor(uint256 value) external onlyOwner {
        require(value <= WAD, "factor>100%");
        closeFactor = value;
        emit CloseFactorUpdated(value);
    }

    /// @notice 限制可借款的最高 LTV 档位。极端市场下可设 3 以暂停 75%/80% 档。
    function setMaxBorrowTier(uint256 tier) external onlyOwner {
        require(tier >= 1 && tier <= MAX_TIERS, "bad tier");
        maxBorrowTier = tier;
        emit MaxBorrowTierUpdated(tier);
    }

    // ==================== View: token-aware ====================

    function getMaxLTV(address token, uint256 tier) external view returns (uint256) {
        return tierConfig[token][tier].maxLTV;
    }

    function getLiquidationThreshold(address token, uint256 tier) external view returns (uint256) {
        return tierConfig[token][tier].liquidationThreshold;
    }

    // ==================== View: ETH convenience (back-compat) ====================

    function getMaxBorrowTier() external view returns (uint256) {
        return maxBorrowTier;
    }

    function getLiquidationBonus() external view returns (uint256) {
        return liquidationBonus;
    }

    function getCloseFactor() external view returns (uint256) {
        return closeFactor;
    }

    function getMaxLTV(uint256 tier) external view returns (uint256) {
        return tierConfig[ETH][tier].maxLTV;
    }

    function getLiquidationThreshold(uint256 tier) external view returns (uint256) {
        return tierConfig[ETH][tier].liquidationThreshold;
    }

    function validateBorrow(uint256 tier, uint256 collateralValueWad, uint256 debtWad) external view {
        require(collateralValueWad > 0, "no collateral");
        require(tier <= maxBorrowTier, "tier disabled");
        uint256 ltv = debtWad * WAD / collateralValueWad;
        require(ltv <= tierConfig[ETH][tier].maxLTV, "ltv too high");
    }

    function getHealthFactor(uint256 tier, uint256 collateralValueWad, uint256 debtWad) public view returns (uint256) {
        if (debtWad == 0) return type(uint256).max;
        if (collateralValueWad == 0) return 0;
        return collateralValueWad * tierConfig[ETH][tier].liquidationThreshold / debtWad;
    }

    // ==================== Internal ====================

    function _setTier(address token, uint256 tier, uint256 maxLTV, uint256 liquidationThreshold) internal {
        require(token != address(0), "zero token");
        require(tier >= 1 && tier <= MAX_TIERS, "bad tier");
        require(maxLTV <= 9e17, "maxLTV>90%");
        require(liquidationThreshold > maxLTV, "LT<=maxLTV");
        require(liquidationThreshold <= 95e16, "LT>95%");
        tierConfig[token][tier] = TierConfig(maxLTV, liquidationThreshold);
        emit TierUpdated(token, tier, maxLTV, liquidationThreshold);
    }
}
