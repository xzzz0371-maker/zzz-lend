// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @notice Chainlink 价格预言机适配器。实现 IPriceOracle，可无缝替换 MockPriceOracle。
/// 安全机制：freshness(stale)、deviation、pause、fallback 缓存。所有阈值由 PARAM_ADMIN 配置。
contract ChainlinkOracle is AccessControl, IPriceOracle {
    uint256 public constant WAD = 1e18;
    uint256 public constant PRICE_DECIMALS = 8;

    bytes32 public constant PARAM_ADMIN_ROLE = keccak256("PARAM_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    struct Feed {
        IAggregatorV3 aggregator;
        uint8 decimals;
    }

    mapping(address => Feed) public feeds;
    mapping(address => uint256) public lastPrice;
    mapping(address => uint256) public lastPriceAt;
    /// @notice 最近一次"正常（未偏差）"采样价，作为偏差比较的稳定基准（F5）。
    mapping(address => uint256) public lastValidPrice;

    uint256 public maxStaleness = 3600;
    uint256 public maxDeviation = 3e17;
    uint256 public fallbackMaxAge = 86400;
    bool public paused;
    bool public useFallback;

    /// @notice 最近一次 updatePrice 是否检测到价格异常（偏差 > maxDeviation）。
    mapping(address => bool) public priceAnomalous;

    event FeedSet(address indexed asset, address aggregator);
    event FeedRemoved(address indexed asset);
    event PriceUpdated(address indexed asset, uint256 price);
    event PriceAnomalyDetected(address indexed asset, uint256 lastPrice, uint256 newPrice);
    event MaxStalenessUpdated(uint256 value);
    event MaxDeviationUpdated(uint256 value);
    event FallbackMaxAgeUpdated(uint256 value);
    event Paused(bool state);
    event FallbackMode(bool state);

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PARAM_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ==================== Admin (PARAM_ADMIN) ====================

    function setFeed(address asset, IAggregatorV3 aggregator, uint8 decimals) external onlyRole(PARAM_ADMIN_ROLE) {
        require(asset != address(0), "zero asset");
        require(address(aggregator) != address(0), "zero aggregator");
        feeds[asset] = Feed(aggregator, decimals);
        emit FeedSet(asset, address(aggregator));
    }

    function removeFeed(address asset) external onlyRole(PARAM_ADMIN_ROLE) {
        delete feeds[asset];
        emit FeedRemoved(asset);
    }

    function setMaxStaleness(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value >= 300 && value <= 7 days, "staleness out of bounds");
        maxStaleness = value;
        emit MaxStalenessUpdated(value);
    }

    function setMaxDeviation(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value >= 1e17 && value <= 2e18, "deviation out of bounds");
        maxDeviation = value;
        emit MaxDeviationUpdated(value);
    }

    function setFallbackMaxAge(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value >= 3600 && value <= 30 days, "age out of bounds");
        fallbackMaxAge = value;
        emit FallbackMaxAgeUpdated(value);
    }

    // ==================== Pause / Fallback (PAUSER) ====================

    function pause() external onlyRole(PAUSER_ROLE) {
        paused = true;
        emit Paused(true);
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        paused = false;
        emit Paused(false);
    }

    function enableFallback() external onlyRole(PAUSER_ROLE) {
        useFallback = true;
        emit FallbackMode(true);
    }

    function disableFallback() external onlyRole(PAUSER_ROLE) {
        useFallback = false;
        emit FallbackMode(false);
    }

    // ==================== IPriceOracle ====================

    /// @notice 返回 8 位小数价格（view）。stale 仍会 revert；偏差过大时**不 revert**，返回新价格
    ///         （让清算等可以继续执行）。偏差事件由 updatePrice 触发。
    function getAssetPrice(address asset) external view returns (uint256) {
        require(!paused, "oracle paused");
        if (useFallback) return _getFallbackPrice(asset);
        (uint256 p,) = _readPrice(asset);
        return p;
    }

    /// @notice 采样入口（任何人可调用）：读取并缓存价格。偏差过大时返回新价格并触发 PriceAnomalyDetected。
    function updatePrice(address asset) external returns (uint256) {
        require(!paused, "oracle paused");
        if (useFallback) {
            uint256 p = _getFallbackPrice(asset);
            lastPrice[asset] = p;
            lastPriceAt[asset] = block.timestamp;
            return p;
        }
        (uint256 p, bool anomalous) = _readPrice(asset);
        priceAnomalous[asset] = anomalous;
        if (anomalous) emit PriceAnomalyDetected(asset, lastPrice[asset], p);
        lastPrice[asset] = p;
        lastPriceAt[asset] = block.timestamp;
        if (!anomalous) lastValidPrice[asset] = p; // 仅正常价更新基准（F5）
        emit PriceUpdated(asset, p);
        return p;
    }

    /// @notice 价格异常判断。正常模式下**实时**读取最新价并与基准价（lastPrice）内联计算偏差，
    ///         不依赖 updatePrice() 先被调用（修复 F5 监控缺口）；fallback 模式用缓存标记。
    ///         注意：正常模式下若 feed stale，本函数 revert（与 getAssetPrice 一致，fail-closed）。
    function isPriceAnomalous(address asset) external view returns (bool) {
        if (useFallback) return priceAnomalous[asset];
        (uint256 price, bool anomalous) = _readPrice(asset);
        return anomalous;
    }

    // ==================== Internal ====================

    /// @notice 读取并校验价格。返回 (价格, 是否偏差异常)。stale 仍 revert；偏差不 revert。
    function _readPrice(address asset) internal view returns (uint256 price, bool anomalous) {
        Feed storage f = feeds[asset];
        require(address(f.aggregator) != address(0), "no feed");
        (, int256 answer,, uint256 updatedAt,) = f.aggregator.latestRoundData();
        require(answer > 0, "invalid price");
        require(block.timestamp >= updatedAt, "future price");
        require(block.timestamp - updatedAt <= maxStaleness, "stale price");
        price = _scale(uint256(answer), f.decimals);
        uint256 base = lastValidPrice[asset];
        if (base > 0) {
            uint256 diff = price > base ? price - base : base - price;
            if (diff * WAD > maxDeviation * base) anomalous = true;
        }
    }

    /// @notice 返回缓存价（updatePrice 采样）。fallback 仅用于短时中断：无法读取实时 feed 时
    ///         不做偏差校验（缓存价即基准价），靠 fallbackMaxAge 限制缓存时效；
    ///         F5 设计取舍：长中断/价格大幅变动后应由人工（PAUSER）介入，而非长期运行于旧价。
    function _getFallbackPrice(address asset) internal view returns (uint256) {
        uint256 p = lastPrice[asset];
        require(p > 0, "no cached price");
        require(block.timestamp - lastPriceAt[asset] <= fallbackMaxAge, "fallback stale");
        return p;
    }

    function _scale(uint256 answer, uint8 decimals) internal pure returns (uint256) {
        if (decimals == PRICE_DECIMALS) return answer;
        if (decimals > PRICE_DECIMALS) return answer / (10 ** (decimals - PRICE_DECIMALS));
        return answer * (10 ** (PRICE_DECIMALS - decimals));
    }
}
