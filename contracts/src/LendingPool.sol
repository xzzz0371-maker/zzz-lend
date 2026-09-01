// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IInterestRateModel} from "./InterestRateModel.sol";
import {IRiskManager} from "./RiskManager.sol";
import {ILiquidationManager} from "./LiquidationManager.sol";
import {IReserveManager} from "./ReserveManager.sol";

contract LendingPool is AccessControl, Pausable, ReentrancyGuard {
    uint256 public constant WAD = 1e18;
    uint256 public constant MAX_TIERS = 5;
    uint256 public constant SECONDS_PER_YEAR = 31536000;
    uint256 public constant USDC_SCALE = 1e12;
    uint256 public constant PRICE_SCALE = 1e8;
    uint256 public constant DUST_THRESHOLD = 100;
    uint256 public constant MIN_SUPPLY = 10e6; // 最小存款 10 USDC（6位小数）
    uint256 public constant MIN_BORROW = 100e6; // 最小借款 100 USDC
    uint256 public constant MIN_COLLATERAL = 0.01 ether; // 最小抵押 0.01 ETH
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    bytes32 public constant PARAM_ADMIN_ROLE = keccak256("PARAM_ADMIN_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    IERC20 public immutable usdc;
    IPriceOracle public priceOracle;
    IInterestRateModel public interestRateModel;
    IRiskManager public riskManager;
    ILiquidationManager public liquidationManager;
    IReserveManager public reserveManager;

    struct UserPosition {
        uint256 shares;
        uint256 collateral;
        uint256 borrowNorm;
        uint256 tier;
    }

    mapping(address => UserPosition) public positions;

    uint256 public supplyIndex = WAD;
    uint256 public totalShares;
    uint256 public cash;
    uint256 public totalReserve;
    uint256 public lastAccrual;
    uint256 public treasuryAccrued;
    uint256 public reserveTargetRatio = 3e16;
    uint256 public reserveFactor = 5e16;
    uint256 public treasuryFactor = 3e16;
    address public treasuryAddress;

    mapping(uint256 => uint256) public borrowIndexByTier;
    mapping(uint256 => uint256) public totalNormalizedByTier;

    event Supplied(address indexed user, uint256 amount, uint256 shares);
    event Withdrawn(address indexed user, uint256 amount, uint256 shares);
    event CollateralSupplied(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 tier, uint256 amount, uint256 newLtv, uint256 healthFactor);
    event Repaid(address indexed user, uint256 amount, uint256 remainingDebt);
    event Liquidated(
        address indexed liquidator,
        address indexed target,
        uint256 debtCovered,
        uint256 collateralSeized,
        uint256 postHealthFactor
    );
    event InterestAccrued(uint256 interest, uint256 intervalSeconds);
    event BadDebtRealized(
        address indexed user,
        uint256 badDebtAmount,
        uint256 coveredByReserve,
        uint256 lossToDepositors,
        uint256 oldSupplyIndex,
        uint256 newSupplyIndex
    );
    event ReserveSkimmed(uint256 amount);
    event ReserveTargetRatioUpdated(uint256 value);
    event ReserveFactorUpdated(uint256 value);
    event TreasuryFactorUpdated(uint256 value);
    event ReserveOverflowTransferred(uint256 amount);
    event TreasuryAddressUpdated(address value);
    event TreasuryCollected(uint256 amount, address to);

    constructor(
        IERC20 usdc_,
        IPriceOracle oracle_,
        IInterestRateModel interestRateModel_,
        IRiskManager riskManager_,
        ILiquidationManager liquidationManager_,
        IReserveManager reserveManager_
    ) {
        usdc = usdc_;
        priceOracle = oracle_;
        interestRateModel = interestRateModel_;
        riskManager = riskManager_;
        liquidationManager = liquidationManager_;
        reserveManager = reserveManager_;
        lastAccrual = block.timestamp;
        for (uint256 i = 1; i <= MAX_TIERS; i++) {
            borrowIndexByTier[i] = WAD;
        }
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PARAM_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ==================== User actions ====================

    function supply(uint256 amount) external nonReentrant whenNotPaused {
        require(amount >= MIN_SUPPLY, "amount below min");
        _accrue();
        uint256 shares = amount * WAD / supplyIndex;
        require(shares > 0, "shares=0");
        positions[msg.sender].shares += shares;
        totalShares += shares;
        cash += amount;
        emit Supplied(msg.sender, amount, shares);
        require(usdc.transferFrom(msg.sender, address(this), amount), "transfer failed");
    }

    function withdraw(uint256 shares) external nonReentrant {
        require(shares > 0, "shares=0");
        _accrue();
        UserPosition storage pos = positions[msg.sender];
        require(pos.shares >= shares, "insufficient shares");
        uint256 amount = shares * supplyIndex / WAD;
        require(cash >= amount, "insufficient liquidity");
        pos.shares -= shares;
        totalShares -= shares;
        cash -= amount;
        emit Withdrawn(msg.sender, amount, shares);
        require(usdc.transfer(msg.sender, amount), "transfer failed");
    }

    function supplyCollateral() external payable nonReentrant whenNotPaused {
        require(msg.value >= MIN_COLLATERAL, "value below min");
        require(!_oracleAnomalous(), "price anomalous");
        positions[msg.sender].collateral += msg.value;
        emit CollateralSupplied(msg.sender, msg.value);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _accrue();
        UserPosition storage pos = positions[msg.sender];
        require(pos.collateral >= amount, "insufficient collateral");
        uint256 debtWad = _getDebtWad(pos);
        if (debtWad > 0) {
            uint256 newValueWad = (pos.collateral - amount) * priceOracle.getAssetPrice(ETH) / PRICE_SCALE;
            uint256 hf = riskManager.getHealthFactor(pos.tier, newValueWad, debtWad);
            require(hf >= WAD, "unhealthy");
        }
        pos.collateral -= amount;
        emit CollateralWithdrawn(msg.sender, amount);
        _safeSendEth(payable(msg.sender), amount);
    }

    function borrow(uint256 amount, uint256 tier) external nonReentrant whenNotPaused {
        require(amount >= MIN_BORROW, "amount below min");
        require(tier >= 1 && tier <= MAX_TIERS, "bad tier");
        require(!_oracleAnomalous(), "price anomalous");
        _accrue();
        UserPosition storage pos = positions[msg.sender];
        if (pos.borrowNorm > 0) {
            require(pos.tier == tier, "tier locked");
        }
        uint256 debtWad = _getDebtWad(pos);
        uint256 collateralValueWad = _getCollateralValueWad(pos);
        uint256 amountWad = _toWadUsd(amount);
        riskManager.validateBorrow(tier, collateralValueWad, debtWad + amountWad);
        require(cash >= amount, "insufficient liquidity");
        uint256 norm = _mulDivUp(amount, WAD, borrowIndexByTier[tier]);
        pos.borrowNorm += norm;
        pos.tier = tier;
        totalNormalizedByTier[tier] += norm;
        cash -= amount;
        uint256 newLtv = (debtWad + amountWad) * WAD / collateralValueWad;
        uint256 hf = riskManager.getHealthFactor(tier, collateralValueWad, debtWad + amountWad);
        emit Borrowed(msg.sender, tier, amount, newLtv, hf);
        require(usdc.transfer(msg.sender, amount), "transfer failed");
    }

    function repay(uint256 amount) external nonReentrant {
        require(amount > 0, "amount=0");
        _accrue();
        UserPosition storage pos = positions[msg.sender];
        require(pos.borrowNorm > 0, "no debt");
        uint256 debt = _getDebt6(pos);
        uint256 repayAmount = amount == type(uint256).max ? debt : (amount < debt ? amount : debt);
        uint256 normReduction = repayAmount * WAD / borrowIndexByTier[pos.tier];
        if (normReduction > pos.borrowNorm) normReduction = pos.borrowNorm; // 防取整下溢（F1）
        pos.borrowNorm -= normReduction;
        totalNormalizedByTier[pos.tier] -= normReduction;
        if (pos.borrowNorm <= DUST_THRESHOLD) {
            totalNormalizedByTier[pos.tier] -= pos.borrowNorm;
            pos.borrowNorm = 0;
            pos.tier = 0;
        }
        cash += repayAmount;
        uint256 remainingDebt = _getDebtWad(pos);
        emit Repaid(msg.sender, repayAmount, remainingDebt);
        require(usdc.transferFrom(msg.sender, address(this), repayAmount), "transfer failed");
    }

    /// @param minSeizeAmount 清算人接受的最低抵押品（ETH，18 位）。0 表示不限制。
    /// @notice 若预言机被 PAUSER 暂停，读价 revert → 清算一并暂停。
    ///         F9 设计取舍：宁可不清算，也不用可能错误/暂停中的价格清算；PAUSER 暂停 oracle 前应确认无待清算仓位。
    function liquidate(address target, uint256 debtToCover, uint256 minSeizeAmount) external nonReentrant {
        require(target != msg.sender, "self-liquidation");
        require(debtToCover > 0, "amount=0");
        _accrue();
        UserPosition storage pos = positions[target];
        require(pos.borrowNorm > 0, "no debt");
        uint256 debtWad = _getDebtWad(pos);
        uint256 collateralValueWad = _getCollateralValueWad(pos);
        uint256 hf = riskManager.getHealthFactor(pos.tier, collateralValueWad, debtWad);
        require(hf < WAD, "not liquidatable");
        uint256 maxCoverWad = debtWad * riskManager.getCloseFactor() / WAD;
        uint256 coverWad = _toWadUsd(debtToCover);
        if (coverWad > maxCoverWad) coverWad = maxCoverWad;
        if (coverWad > debtWad) coverWad = debtWad;
        require(coverWad > 0, "cover=0");
        uint256 seizeValueWad =
            liquidationManager.computeSeizeValue(collateralValueWad, coverWad, riskManager.getLiquidationBonus());
        uint256 price = priceOracle.getAssetPrice(ETH);
        uint256 seizeCollateral = seizeValueWad * PRICE_SCALE / price;
        if (seizeCollateral > pos.collateral) seizeCollateral = pos.collateral;
        require(seizeCollateral > 0, "seize=0");
        if (minSeizeAmount > 0) require(seizeCollateral >= minSeizeAmount, "seize below min");
        uint256 cover6 = _toUsdc6(coverWad);
        uint256 normReduction = _mulDivUp(cover6, WAD, borrowIndexByTier[pos.tier]);
        if (normReduction > pos.borrowNorm) normReduction = pos.borrowNorm; // 防取整下溢（F1）
        pos.borrowNorm -= normReduction;
        totalNormalizedByTier[pos.tier] -= normReduction;
        if (pos.borrowNorm <= DUST_THRESHOLD) {
            totalNormalizedByTier[pos.tier] -= pos.borrowNorm;
            pos.borrowNorm = 0;
            pos.tier = 0;
        }
        pos.collateral -= seizeCollateral;
        cash += cover6;
        uint256 postHf;
        if (pos.borrowNorm == 0) {
            postHf = type(uint256).max;
        } else {
            postHf = riskManager.getHealthFactor(pos.tier, _getCollateralValueWad(pos), _getDebtWad(pos));
        }
        emit Liquidated(msg.sender, target, cover6, seizeCollateral, postHf);
        require(usdc.transferFrom(msg.sender, address(this), cover6), "transfer failed");
        _safeSendEth(payable(msg.sender), seizeCollateral);
    }

    /// @notice 坏账即时传导：抵押归零仍有债务的仓位，先由风险储备（第一损失缓冲）覆盖可覆盖部分，
    ///         剩余未覆盖部分即时降低 supplyIndex（所有存款人按份额承担），坏账一次性消化、不挂账。
    ///         权限开放：任何人可调用；管理员无法直接降低 supplyIndex，只能经由本函数触发。
    function handleBadDebt(address target) external nonReentrant {
        _accrue();
        UserPosition storage pos = positions[target];
        require(pos.borrowNorm > 0, "no debt");
        require(pos.collateral == 0, "collateral exists");
        uint256 badDebtAmount = _getDebt6(pos);
        uint256 reserveBalance = usdc.balanceOf(address(reserveManager));
        uint256 coveredByReserve = badDebtAmount > reserveBalance ? reserveBalance : badDebtAmount;
        uint256 lossToDepositors = badDebtAmount - coveredByReserve;

        uint256 oldSupplyIndex = supplyIndex;
        uint256 newSupplyIndex = oldSupplyIndex;
        uint256 remaining = lossToDepositors;
        if (remaining > 0) {
            // 1) 存款人按份额承担（最多承担全部净资产，即 supplyIndex 可归零）
            uint256 supplyBefore = getTotalSupply();
            if (supplyBefore > 0) {
                uint256 absorbed = remaining >= supplyBefore ? supplyBefore : remaining;
                newSupplyIndex =
                    absorbed >= supplyBefore ? 0 : oldSupplyIndex * (supplyBefore - absorbed) / supplyBefore;
                supplyIndex = newSupplyIndex;
                remaining -= absorbed;
            }
            // 2) 超出存款人承受的部分由账面储备（第一损失缓冲的未 skim 部分）承担
            if (remaining > 0 && totalReserve > 0) {
                uint256 absorbed = remaining >= totalReserve ? totalReserve : remaining;
                totalReserve -= absorbed;
                remaining -= absorbed;
            }
            // 3) 仍有剩余由 Treasury 承担（协议收入兜底），保证资金守恒不变式始终成立
            if (remaining > 0 && treasuryAccrued > 0) {
                uint256 absorbed = remaining >= treasuryAccrued ? treasuryAccrued : remaining;
                treasuryAccrued -= absorbed;
                remaining -= absorbed;
            }
        }

        // 清除该仓位全部债务（债务归零、抵押品归零）
        totalNormalizedByTier[pos.tier] -= pos.borrowNorm;
        pos.borrowNorm = 0;
        pos.tier = 0;

        if (coveredByReserve > 0) {
            cash += coveredByReserve;
            reserveManager.coverBadDebt(coveredByReserve);
        }
        emit BadDebtRealized(target, badDebtAmount, coveredByReserve, lossToDepositors, oldSupplyIndex, newSupplyIndex);
    }

    function skimReserve() external nonReentrant {
        _accrue();
        uint256 amount = totalReserve > cash ? cash : totalReserve;
        require(amount > 0, "no reserve");
        totalReserve -= amount;
        cash -= amount;
        emit ReserveSkimmed(amount);
        require(usdc.transfer(address(reserveManager), amount), "transfer failed");
    }

    function accrue() external {
        _accrue();
    }

    // ==================== Admin ====================

    function setReserveTargetRatio(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value <= WAD, "ratio>100%");
        reserveTargetRatio = value;
        emit ReserveTargetRatioUpdated(value);
    }

    function setReserveFactor(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value <= WAD, "factor>100%");
        require(value + treasuryFactor <= WAD, "fees>100%");
        reserveFactor = value;
        emit ReserveFactorUpdated(value);
    }

    function setTreasuryFactor(uint256 value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value <= WAD, "fee>100%");
        require(value + reserveFactor <= WAD, "fees>100%");
        treasuryFactor = value;
        emit TreasuryFactorUpdated(value);
    }

    function setTreasuryAddress(address value) external onlyRole(PARAM_ADMIN_ROLE) {
        require(value != address(0), "zero address");
        treasuryAddress = value;
        emit TreasuryAddressUpdated(value);
    }

    /// @notice 任何人可调用：将累计的 Treasury USDC 转给 treasuryAddress。零地址时 revert。
    function collectTreasury() external nonReentrant {
        require(treasuryAddress != address(0), "treasury not set");
        uint256 amount = treasuryAccrued;
        require(amount > 0, "no treasury");
        require(cash >= amount, "insufficient liquidity");
        treasuryAccrued = 0;
        cash -= amount;
        emit TreasuryCollected(amount, treasuryAddress);
        require(usdc.transfer(treasuryAddress, amount), "transfer failed");
    }

    function setPriceOracle(IPriceOracle oracle) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(oracle) != address(0), "zero address");
        priceOracle = oracle;
    }

    function setInterestRateModel(IInterestRateModel model) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(model) != address(0), "zero address");
        interestRateModel = model;
    }

    function setRiskManager(IRiskManager manager) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(manager) != address(0), "zero address");
        riskManager = manager;
    }

    function setLiquidationManager(ILiquidationManager manager) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(manager) != address(0), "zero address");
        liquidationManager = manager;
    }

    function setReserveManager(IReserveManager manager) external onlyRole(PARAM_ADMIN_ROLE) {
        require(address(manager) != address(0), "zero address");
        require(address(manager).code.length > 0, "not a contract");
        reserveManager = manager;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ==================== Views ====================

    function getTotalBorrows() public view returns (uint256) {
        uint256 total = 0;
        for (uint256 t = 1; t <= MAX_TIERS; t++) {
            total += totalNormalizedByTier[t] * borrowIndexByTier[t] / WAD;
        }
        return total;
    }

    function getTotalSupply() public view returns (uint256) {
        return totalShares * supplyIndex / WAD;
    }

    function getUtilization() public view returns (uint256) {
        uint256 totalBorrows = getTotalBorrows();
        uint256 total = cash + totalBorrows;
        if (total == 0) return 0;
        return totalBorrows * WAD / total;
    }

    function getBorrowAPR(uint256 tier) external view returns (uint256) {
        return interestRateModel.getBorrowRatePerSecond(getUtilization(), tier) * SECONDS_PER_YEAR;
    }

    function getSupplyAPR() external view returns (uint256) {
        uint256 avgRate = _getAverageBorrowRate();
        uint256 utilization = getUtilization();
        uint256 totalFee = reserveFactor + treasuryFactor;
        return avgRate * utilization * (WAD - totalFee) / WAD / WAD * SECONDS_PER_YEAR;
    }

    function getDebt(address user) external view returns (uint256) {
        return _getDebtWad(positions[user]);
    }

    function getCollateralValue(address user) external view returns (uint256) {
        return _getCollateralValueWad(positions[user]);
    }

    function getUserHealthFactor(address user) external view returns (uint256) {
        UserPosition storage pos = positions[user];
        uint256 debtWad = _getDebtWad(pos);
        if (debtWad == 0) return type(uint256).max;
        return riskManager.getHealthFactor(pos.tier, _getCollateralValueWad(pos), debtWad);
    }

    function isLiquidatable(address user) external view returns (bool) {
        UserPosition storage pos = positions[user];
        uint256 debtWad = _getDebtWad(pos);
        if (debtWad == 0) return false;
        return riskManager.getHealthFactor(pos.tier, _getCollateralValueWad(pos), debtWad) < WAD;
    }

    function maxBorrowable(address user, uint256 tier) external view returns (uint256) {
        UserPosition storage pos = positions[user];
        uint256 collateralValueWad = _getCollateralValueWad(pos);
        uint256 debtWad = _getDebtWad(pos);
        if (pos.borrowNorm > 0 && pos.tier != tier) return 0;
        uint256 capacity = collateralValueWad * riskManager.getMaxLTV(tier) / WAD;
        if (debtWad >= capacity) return 0;
        return _toUsdc6(capacity - debtWad);
    }

    function getUserPosition(address user)
        external
        view
        returns (
            uint256 shares,
            uint256 collateral,
            uint256 debt,
            uint256 collateralValue,
            uint256 healthFactor,
            uint256 tier,
            bool liquidatable
        )
    {
        UserPosition storage pos = positions[user];
        shares = pos.shares;
        collateral = pos.collateral;
        debt = _getDebtWad(pos);
        collateralValue = _getCollateralValueWad(pos);
        tier = pos.tier;
        if (debt == 0) {
            healthFactor = type(uint256).max;
        } else {
            healthFactor = riskManager.getHealthFactor(pos.tier, collateralValue, debt);
        }
        liquidatable = healthFactor < WAD;
    }

    // ==================== Internal ====================

    /// @notice 存款人分得比例 = 100% - reserveFactor - treasuryFactor（默认 92%）。
    function depositorShare() public view returns (uint256) {
        return WAD - reserveFactor - treasuryFactor;
    }

    function _accrue() internal {
        uint256 currentTimestamp = block.timestamp;
        if (currentTimestamp == lastAccrual) return;
        uint256 dt = currentTimestamp - lastAccrual;
        uint256 utilization = getUtilization();
        uint256 totalInterest = 0;
        for (uint256 t = 1; t <= MAX_TIERS; t++) {
            uint256 totalNorm = totalNormalizedByTier[t];
            if (totalNorm == 0) continue;
            uint256 rate = interestRateModel.getBorrowRatePerSecond(utilization, t);
            uint256 index = borrowIndexByTier[t];
            uint256 interest = totalNorm * index * rate * dt / (WAD * WAD);
            borrowIndexByTier[t] = index + index * rate * dt / WAD;
            totalInterest += interest;
        }
        if (totalInterest == 0) {
            lastAccrual = currentTimestamp;
            return;
        }
        // 固定比例分配：储备 5%、Treasury 3%、存款人 92%（余额为精确余数，保证资金守恒）
        uint256 reserveShare = totalInterest * reserveFactor / WAD;
        uint256 treasuryShare = totalInterest * treasuryFactor / WAD;
        uint256 suppliersShare = totalInterest - reserveShare - treasuryShare;
        if (totalShares > 0) {
            supplyIndex += suppliersShare * WAD / totalShares;
            totalReserve += reserveShare;
            treasuryAccrued += treasuryShare;
        } else {
            totalReserve += totalInterest;
        }
        // 储备溢出自动转 Treasury：储备总资产（账面 + 物理）超过目标时，超额部分转 Treasury
        _overflowReserveToTreasury();
        lastAccrual = currentTimestamp;
        emit InterestAccrued(totalInterest, dt);
    }

    /// @notice 储备目标 = totalBorrows × reserveTargetRatio；储备总资产（账面 totalReserve + 物理
    ///         ReserveManager 余额）超过目标的部分，从账面储备转入 Treasury，储备固定在目标值。
    function _overflowReserveToTreasury() internal {
        uint256 totalBorrows = getTotalBorrows();
        if (totalBorrows == 0) return;
        uint256 reserveTarget = totalBorrows * reserveTargetRatio / WAD;
        uint256 reserveAssets = totalReserve + usdc.balanceOf(address(reserveManager));
        if (reserveAssets <= reserveTarget) return;
        uint256 overflow = reserveAssets - reserveTarget;
        uint256 transferable = overflow > totalReserve ? totalReserve : overflow;
        if (transferable == 0) return;
        totalReserve -= transferable;
        treasuryAccrued += transferable;
        emit ReserveOverflowTransferred(transferable);
    }

    function _getDebt6(UserPosition storage pos) internal view returns (uint256) {
        if (pos.borrowNorm == 0) return 0;
        return (pos.borrowNorm * borrowIndexByTier[pos.tier] + WAD - 1) / WAD;
    }

    function _getDebtWad(UserPosition storage pos) internal view returns (uint256) {
        if (pos.borrowNorm == 0) return 0;
        // 债务美元价值 = USDC 数量 × USDC/USD 价格（支持 USDC 溢价/脱锚）
        return _toWadUsd(_getDebt6(pos));
    }

    /// @notice USDC/USD 价格（8 位小数）。必须 > 0。
    function _usdcPrice() internal view returns (uint256) {
        uint256 p = priceOracle.getAssetPrice(address(usdc));
        require(p > 0, "bad usdc price");
        return p;
    }

    /// @notice 任一关键资产价格被标记异常（偏差超阈值）→ 暂停新增借款/新增抵押。
    function _oracleAnomalous() internal view returns (bool) {
        return priceOracle.isPriceAnomalous(ETH) || priceOracle.isPriceAnomalous(address(usdc));
    }

    /// @notice USDC 数量(6位) → 美元 WAD = amount × price / 1e8 × 1e12（向上取整）。
    function _toWadUsd(uint256 usdc6) internal view returns (uint256) {
        return (usdc6 * _usdcPrice() * USDC_SCALE + PRICE_SCALE - 1) / PRICE_SCALE;
    }

    /// @notice 美元 WAD → USDC 数量(6位) = wad × 1e8 / (price × 1e12)（向下取整）。
    function _toUsdc6(uint256 wadUsd) internal view returns (uint256) {
        return wadUsd * PRICE_SCALE / (_usdcPrice() * USDC_SCALE);
    }

    function _getCollateralValueWad(UserPosition storage pos) internal view returns (uint256) {
        return pos.collateral * priceOracle.getAssetPrice(ETH) / PRICE_SCALE;
    }

    function _getAverageBorrowRate() internal view returns (uint256) {
        uint256 totalBorrows = 0;
        uint256 weighted = 0;
        uint256 utilization = getUtilization();
        for (uint256 t = 1; t <= MAX_TIERS; t++) {
            uint256 norm = totalNormalizedByTier[t];
            if (norm == 0) continue;
            uint256 borrows = norm * borrowIndexByTier[t] / WAD;
            totalBorrows += borrows;
            weighted += borrows * interestRateModel.getBorrowRatePerSecond(utilization, t);
        }
        if (totalBorrows == 0) return 0;
        return weighted / totalBorrows;
    }

    function _mulDivUp(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        return (a * b + c - 1) / c;
    }

    /// @notice 用 call 发送 ETH（不受 2300 gas 限制），失败即 revert。重入由 ReentrancyGuard 拦截。
    function _safeSendEth(address payable to, uint256 amount) internal {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "eth transfer failed");
    }
}
