// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

/// @notice 风险引擎：只计算风险等级并给出参数调整【建议】，绝不修改任何资金或协议状态。
/// 实际参数调整必须由 PARAM_ADMIN / PAUSER 手动执行。
interface ILendingPoolView {
    function cash() external view returns (uint256);

    function getTotalSupply() external view returns (uint256);

    function getUtilization() external view returns (uint256);
}

contract RiskEngine is AccessControl {
    uint256 public constant WAD = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes32 public constant PARAM_ADMIN_ROLE = keccak256("PARAM_ADMIN_ROLE");

    enum RiskLevel {
        LOW,
        MEDIUM,
        HIGH,
        EXTREME
    }

    IPriceOracle public oracle;
    ILendingPoolView public immutable pool;

    // 年化波动率阈值（WAD）
    uint256 public lowVolThreshold = 3e17;
    uint256 public highVolThreshold = 6e17;
    uint256 public extremeVolThreshold = 1e18;

    // Utilization 阈值（WAD）
    uint256 public lowUtilThreshold = 5e17;
    uint256 public highUtilThreshold = 75e16;
    uint256 public extremeUtilThreshold = 9e17;

    // LTV / LT 比值阈值
    uint256 public ltvLowRatio = 6e17;
    uint256 public ltvHighRatio = 8e17;
    uint256 public ltvExtremeRatio = 1e18;

    // 流动性比率（可用流动性 / 总存款）阈值：>=high->LOW, >=medium->MEDIUM, >=low->HIGH, else EXTREME
    uint256 public liqHighThreshold = 25e16;
    uint256 public liqMediumThreshold = 1e17;
    uint256 public liqLowThreshold = 1e16;

    // 波动率采样
    uint256 public sampleWindow = 24;
    uint256 public minSampleInterval = 3600;
    mapping(address => uint256[]) public samples;
    mapping(address => uint256) public lastSampleAt;

    event SampleRecorded(address indexed asset, uint256 price);
    event VolThresholdsUpdated(uint256 low, uint256 high, uint256 extreme);
    event UtilThresholdsUpdated(uint256 low, uint256 high, uint256 extreme);
    event LtvRatioThresholdsUpdated(uint256 low, uint256 high, uint256 extreme);
    event LiquidityThresholdsUpdated(uint256 high, uint256 medium, uint256 low);
    event SamplingParamsUpdated(uint256 window, uint256 interval);

    constructor(address oracle_, address pool_) {
        oracle = IPriceOracle(oracle_);
        pool = ILendingPoolView(pool_);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PARAM_ADMIN_ROLE, msg.sender);
    }

    // ==================== Admin (PARAM_ADMIN, 带上下限) ====================

    function setOracle(address o) external onlyRole(PARAM_ADMIN_ROLE) {
        require(o != address(0), "zero address");
        oracle = IPriceOracle(o);
    }

    function setVolThresholds(uint256 low, uint256 high, uint256 extreme) external onlyRole(PARAM_ADMIN_ROLE) {
        _requireOrdered(low, high, extreme, 1e16, 2e18);
        lowVolThreshold = low;
        highVolThreshold = high;
        extremeVolThreshold = extreme;
        emit VolThresholdsUpdated(low, high, extreme);
    }

    function setUtilThresholds(uint256 low, uint256 high, uint256 extreme) external onlyRole(PARAM_ADMIN_ROLE) {
        _requireOrdered(low, high, extreme, 1e16, WAD);
        lowUtilThreshold = low;
        highUtilThreshold = high;
        extremeUtilThreshold = extreme;
        emit UtilThresholdsUpdated(low, high, extreme);
    }

    function setLtvRatioThresholds(uint256 low, uint256 high, uint256 extreme) external onlyRole(PARAM_ADMIN_ROLE) {
        _requireOrdered(low, high, extreme, 1e16, WAD);
        ltvLowRatio = low;
        ltvHighRatio = high;
        ltvExtremeRatio = extreme;
        emit LtvRatioThresholdsUpdated(low, high, extreme);
    }

    function setLiquidityThresholds(uint256 high, uint256 medium, uint256 low) external onlyRole(PARAM_ADMIN_ROLE) {
        require(low < medium && medium < high, "not ordered");
        require(high >= 1e16 && high <= WAD, "high out of bounds");
        require(low >= 1e14, "low too small");
        liqHighThreshold = high;
        liqMediumThreshold = medium;
        liqLowThreshold = low;
        emit LiquidityThresholdsUpdated(high, medium, low);
    }

    function setSamplingParams(uint256 window_, uint256 interval_) external onlyRole(PARAM_ADMIN_ROLE) {
        require(window_ >= 2 && window_ <= 100, "window out of bounds");
        require(interval_ >= 60 && interval_ <= 7 days, "interval out of bounds");
        sampleWindow = window_;
        minSampleInterval = interval_;
        emit SamplingParamsUpdated(window_, interval_);
    }

    // ==================== 波动率采样（permissionless，带最小间隔） ====================

    function recordSample(address asset) external {
        require(block.timestamp - lastSampleAt[asset] >= minSampleInterval, "sample too soon");
        uint256 price = oracle.getAssetPrice(asset);
        samples[asset].push(price);
        uint256 len = samples[asset].length;
        if (len > sampleWindow) {
            for (uint256 i = 0; i < len - 1; i++) {
                samples[asset][i] = samples[asset][i + 1];
            }
            samples[asset].pop();
        }
        lastSampleAt[asset] = block.timestamp;
        emit SampleRecorded(asset, price);
    }

    function getSampleCount(address asset) external view returns (uint256) {
        return samples[asset].length;
    }

    /// @notice 每周期收益率标准差（WAD）。样本数 < 2 时返回 0（便于 auto 计算）。
    function getPerPeriodVolatility(address asset) public view returns (uint256) {
        uint256 n = samples[asset].length;
        if (n < 2) return 0;
        int256[] memory ret = new int256[](n - 1);
        for (uint256 i = 1; i < n; i++) {
            ret[i - 1] = int256(samples[asset][i] * WAD / samples[asset][i - 1]) - int256(WAD);
        }
        int256 sum;
        for (uint256 i = 0; i < ret.length; i++) {
            sum += ret[i];
        }
        int256 mean = sum / int256(ret.length);
        int256 sumSq;
        for (uint256 i = 0; i < ret.length; i++) {
            int256 d = ret[i] - mean;
            sumSq += d * d;
        }
        uint256 variance = uint256(sumSq) / ret.length;
        return _sqrt(variance);
    }

    /// @notice 年化波动率 = 每周期标准差 × sqrt(每年周期数)。
    function getAnnualizedVolatility(address asset) public view returns (uint256) {
        uint256 periodsPerYear = SECONDS_PER_YEAR / minSampleInterval;
        return getPerPeriodVolatility(asset) * _sqrt(periodsPerYear);
    }

    // ==================== 风险等级 ====================

    /// @notice 纯函数：输入因子直接计算风险等级，不触碰任何状态。
    /// @param volatilityAnnualized 年化波动率（WAD）
    /// @param utilization 利用率（WAD）
    /// @param ltv 当前 LTV（WAD）
    /// @param liquidationThreshold 清算阈值（WAD）
    /// @param liquidityRatio 可用流动性/总存款（WAD）
    function getRiskLevel(
        uint256 volatilityAnnualized,
        uint256 utilization,
        uint256 ltv,
        uint256 liquidationThreshold,
        uint256 liquidityRatio
    ) public view returns (RiskLevel) {
        require(liquidityRatio <= WAD, "invalid liquidity");
        RiskLevel level = RiskLevel.LOW;

        RiskLevel volLevel =
            _levelFromThresholds(volatilityAnnualized, lowVolThreshold, highVolThreshold, extremeVolThreshold);
        RiskLevel utilLevel =
            _levelFromThresholds(utilization, lowUtilThreshold, highUtilThreshold, extremeUtilThreshold);

        RiskLevel liqLevel;
        if (liquidityRatio >= liqHighThreshold) {
            liqLevel = RiskLevel.LOW;
        } else if (liquidityRatio >= liqMediumThreshold) {
            liqLevel = RiskLevel.MEDIUM;
        } else if (liquidityRatio >= liqLowThreshold) {
            liqLevel = RiskLevel.HIGH;
        } else {
            liqLevel = RiskLevel.EXTREME;
        }

        RiskLevel ltvLevel;
        if (liquidationThreshold == 0) {
            ltvLevel = RiskLevel.EXTREME;
        } else {
            uint256 ratio = ltv * WAD / liquidationThreshold;
            if (ratio < ltvLowRatio) {
                ltvLevel = RiskLevel.LOW;
            } else if (ratio < ltvHighRatio) {
                ltvLevel = RiskLevel.MEDIUM;
            } else if (ratio < ltvExtremeRatio) {
                ltvLevel = RiskLevel.HIGH;
            } else {
                ltvLevel = RiskLevel.EXTREME;
            }
        }

        if (volLevel > level) level = volLevel;
        if (utilLevel > level) level = utilLevel;
        if (liqLevel > level) level = liqLevel;
        if (ltvLevel > level) level = ltvLevel;
        return level;
    }

    function isExtreme(uint256 vol, uint256 utilization, uint256 ltv, uint256 lt, uint256 liquidity)
        external
        view
        returns (bool)
    {
        return getRiskLevel(vol, utilization, ltv, lt, liquidity) == RiskLevel.EXTREME;
    }

    /// @notice 自动风险等级：波动率取引擎采样（ETH），Utilization 与流动性直接从 LendingPool 读取。
    ///         LTV / 清算阈值仍由调用方传入（仓位相关）。
    function calculateRiskLevelAuto(uint256 ltv, uint256 liquidationThreshold) external view returns (RiskLevel) {
        uint256 vol = getAnnualizedVolatility(ETH);
        uint256 utilization = pool.getUtilization();
        uint256 totalSupply = pool.getTotalSupply();
        // 空池无流动性风险 → 按 100% 流动性处理
        uint256 liquidity = totalSupply == 0 ? WAD : pool.cash() * WAD / totalSupply;
        return getRiskLevel(vol, utilization, ltv, liquidationThreshold, liquidity);
    }

    /// @notice 只输出建议，不执行。
    function getRecommendation(RiskLevel level) external pure returns (string memory) {
        if (level == RiskLevel.LOW) return "normal parameters; all LTV tiers open";
        if (level == RiskLevel.MEDIUM) return "monitor; consider increasing base rate";
        if (level == RiskLevel.HIGH) return "lower high LTV tier limits; increase rates";
        return "pause high LTV tier borrowing; switch to HIGH_VOLATILITY or EXTREME preset";
    }

    // ==================== Internal ====================

    function _levelFromThresholds(uint256 v, uint256 t1, uint256 t2, uint256 t3) internal pure returns (RiskLevel) {
        if (v < t1) return RiskLevel.LOW;
        if (v < t2) return RiskLevel.MEDIUM;
        if (v < t3) return RiskLevel.HIGH;
        return RiskLevel.EXTREME;
    }

    function _requireOrdered(uint256 a, uint256 b, uint256 c, uint256 min_, uint256 max_) internal pure {
        require(a >= min_ && c <= max_, "threshold out of bounds");
        require(a < b && b < c, "not ordered");
    }

    function _sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
