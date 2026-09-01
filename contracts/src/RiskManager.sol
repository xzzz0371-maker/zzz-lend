// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IRiskManager {
    function getMaxLTV(uint256 tier) external view returns (uint256);

    function getLiquidationThreshold(uint256 tier) external view returns (uint256);

    function getLiquidationBonus() external view returns (uint256);

    function getCloseFactor() external view returns (uint256);

    function getMaxBorrowTier() external view returns (uint256);

    /// @notice Reverts if `debtWad` exceeds `maxLTV` of `collateralValueWad` for the tier.
    function validateBorrow(uint256 tier, uint256 collateralValueWad, uint256 debtWad) external view;

    /// @notice Health factor in WAD: collateralValueWad * LT / debtWad. Max value if no debt.
    function getHealthFactor(uint256 tier, uint256 collateralValueWad, uint256 debtWad) external view returns (uint256);
}

contract RiskManager is Ownable, IRiskManager {
    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_TIERS = 5;

    struct TierConfig {
        uint256 maxLTV;
        uint256 liquidationThreshold;
    }

    mapping(uint256 => TierConfig) public tiers;
    uint256 public liquidationBonus = 5e16;
    uint256 public closeFactor = 5e17;
    uint256 public maxBorrowTier = MAX_TIERS;

    event TierUpdated(uint256 tier, uint256 maxLTV, uint256 liquidationThreshold);
    event LiquidationBonusUpdated(uint256 value);
    event CloseFactorUpdated(uint256 value);
    event MaxBorrowTierUpdated(uint256 tier);

    constructor() Ownable(msg.sender) {
        tiers[1] = TierConfig(5e17, 6e17);
        tiers[2] = TierConfig(6e17, 7e17);
        tiers[3] = TierConfig(7e17, 78e16);
        tiers[4] = TierConfig(75e16, 85e16);
        tiers[5] = TierConfig(8e17, 9e17);
    }

    function setTier(uint256 tier, uint256 maxLTV, uint256 liquidationThreshold) external onlyOwner {
        require(tier >= 1 && tier <= MAX_TIERS, "bad tier");
        require(maxLTV <= 9e17, "maxLTV>90%");
        require(liquidationThreshold > maxLTV, "LT<=maxLTV");
        require(liquidationThreshold <= 95e16, "LT>95%");
        tiers[tier] = TierConfig(maxLTV, liquidationThreshold);
        emit TierUpdated(tier, maxLTV, liquidationThreshold);
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

    function getMaxBorrowTier() external view returns (uint256) {
        return maxBorrowTier;
    }

    function getMaxLTV(uint256 tier) external view returns (uint256) {
        return tiers[tier].maxLTV;
    }

    function getLiquidationThreshold(uint256 tier) external view returns (uint256) {
        return tiers[tier].liquidationThreshold;
    }

    function getLiquidationBonus() external view returns (uint256) {
        return liquidationBonus;
    }

    function getCloseFactor() external view returns (uint256) {
        return closeFactor;
    }

    function validateBorrow(uint256 tier, uint256 collateralValueWad, uint256 debtWad) external view {
        require(collateralValueWad > 0, "no collateral");
        require(tier <= maxBorrowTier, "tier disabled");
        uint256 ltv = debtWad * WAD / collateralValueWad;
        require(ltv <= tiers[tier].maxLTV, "ltv too high");
    }

    function getHealthFactor(uint256 tier, uint256 collateralValueWad, uint256 debtWad) public view returns (uint256) {
        if (debtWad == 0) return type(uint256).max;
        if (collateralValueWad == 0) return 0;
        return collateralValueWad * tiers[tier].liquidationThreshold / debtWad;
    }
}
