// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IInterestRateModel {
    /// @notice Returns the per-second borrow rate in WAD given utilization (WAD) and tier (1..5).
    function getBorrowRatePerSecond(uint256 utilization, uint256 tier) external view returns (uint256);
}

contract InterestRateModel is Ownable, IInterestRateModel {
    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    uint256 public constant MAX_TIERS = 5;

    enum MarketPreset {
        NORMAL,
        HIGH_VOLATILITY,
        EXTREME
    }

    uint256 public baseRatePerSecond;
    uint256 public slope1PerSecond;
    uint256 public slope2PerSecond;
    uint256 public kinkUtilization = 8e17;
    uint256[6] public tierPremiumPerSecond;

    MarketPreset public activePreset = MarketPreset.NORMAL;
    address public marketGovernor;

    event ParamsUpdated(uint256 baseRate, uint256 slope1, uint256 slope2, uint256 kink);
    event TierPremiumUpdated(uint256 tier, uint256 premium);
    event PresetApplied(MarketPreset preset);
    event MarketGovernorUpdated(address governor);

    constructor() Ownable(msg.sender) {
        _applyNormal();
    }

    function setParams(uint256 baseRate, uint256 slope1, uint256 slope2, uint256 kink) external onlyOwner {
        require(kink <= WAD, "kink>WAD");
        baseRatePerSecond = _aprToPerSecond(baseRate);
        slope1PerSecond = _aprToPerSecond(slope1);
        slope2PerSecond = _aprToPerSecond(slope2);
        kinkUtilization = kink;
        emit ParamsUpdated(baseRate, slope1, slope2, kink);
    }

    function setTierPremium(uint256 tier, uint256 premium) external onlyOwner {
        require(tier >= 1 && tier <= MAX_TIERS, "bad tier");
        tierPremiumPerSecond[tier] = _aprToPerSecond(premium);
        emit TierPremiumUpdated(tier, premium);
    }

    /// @notice 设置市场参数切换者（通常为 LendingPool 的 PARAM_ADMIN 持有者）。
    function setMarketGovernor(address governor) external onlyOwner {
        require(governor != address(0), "zero address");
        marketGovernor = governor;
        emit MarketGovernorUpdated(governor);
    }

    /// @notice 应用预设市场参数。owner 或 marketGovernor 可切换。
    function applyPreset(MarketPreset preset) external {
        require(msg.sender == owner() || msg.sender == marketGovernor, "not governor");
        if (preset == MarketPreset.NORMAL) {
            _applyNormal();
        } else if (preset == MarketPreset.HIGH_VOLATILITY) {
            _applyHighVolatility();
        } else {
            _applyExtreme();
        }
        activePreset = preset;
        emit PresetApplied(preset);
    }

    /// @notice 正常市场：base 低、kink 80%、斜率平缓。
    function _applyNormal() internal {
        baseRatePerSecond = _aprToPerSecond(0.02e18);
        slope1PerSecond = _aprToPerSecond(0.08e18);
        slope2PerSecond = _aprToPerSecond(0.6e18);
        kinkUtilization = 8e17;
        tierPremiumPerSecond[1] = _aprToPerSecond(0);
        tierPremiumPerSecond[2] = _aprToPerSecond(0.005e18);
        tierPremiumPerSecond[3] = _aprToPerSecond(0.015e18);
        tierPremiumPerSecond[4] = _aprToPerSecond(0.03e18);
        tierPremiumPerSecond[5] = _aprToPerSecond(0.06e18);
    }

    /// @notice 高波动市场：base 中等、kink 65%、斜率较陡。
    function _applyHighVolatility() internal {
        baseRatePerSecond = _aprToPerSecond(0.02e18);
        slope1PerSecond = _aprToPerSecond(0.2e18);
        slope2PerSecond = _aprToPerSecond(1.5e18);
        kinkUtilization = 65e16;
        tierPremiumPerSecond[1] = _aprToPerSecond(0);
        tierPremiumPerSecond[2] = _aprToPerSecond(0.01e18);
        tierPremiumPerSecond[3] = _aprToPerSecond(0.03e18);
        tierPremiumPerSecond[4] = _aprToPerSecond(0.05e18);
        tierPremiumPerSecond[5] = _aprToPerSecond(0.08e18);
    }

    /// @notice 极端市场：base 高、kink 50%、斜率陡峭。高 LTV 档借款由 RiskManager 另行暂停。
    function _applyExtreme() internal {
        baseRatePerSecond = _aprToPerSecond(0.05e18);
        slope1PerSecond = _aprToPerSecond(0.4e18);
        slope2PerSecond = _aprToPerSecond(3e18);
        kinkUtilization = 5e17;
        tierPremiumPerSecond[1] = _aprToPerSecond(0);
        tierPremiumPerSecond[2] = _aprToPerSecond(0.02e18);
        tierPremiumPerSecond[3] = _aprToPerSecond(0.05e18);
        tierPremiumPerSecond[4] = _aprToPerSecond(0.08e18);
        tierPremiumPerSecond[5] = _aprToPerSecond(0.12e18);
    }

    function getBorrowRatePerSecond(uint256 utilization, uint256 tier) public view returns (uint256) {
        uint256 rate = baseRatePerSecond;
        if (utilization <= kinkUtilization) {
            rate += slope1PerSecond * utilization / WAD;
        } else {
            rate += slope1PerSecond * kinkUtilization / WAD;
            rate += slope2PerSecond * (utilization - kinkUtilization) / WAD;
        }
        return rate + tierPremiumPerSecond[tier];
    }

    function getBorrowAPR(uint256 utilization, uint256 tier) external view returns (uint256) {
        return getBorrowRatePerSecond(utilization, tier) * SECONDS_PER_YEAR;
    }

    function _aprToPerSecond(uint256 apr) internal pure returns (uint256) {
        return apr / SECONDS_PER_YEAR;
    }
}
