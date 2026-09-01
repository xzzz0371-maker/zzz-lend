# ZZZ Lend — 完整项目文档

> **单一总文档**：汇总产品、架构、合约、阶段进度、测试、安全、部署与待办（原分阶段/交接/配置文档已并入后删除）。
> 归总日期：2026-08-29
> 新接手者先读 \docs/接手指南.md\（快速上手/关键实现/部署运维）。 ｜ 状态：阶段 7 已部署 Sepolia（2026-08-31）+ 阶段 8 前端已实现（2026-09-01，见 `frontend/README.md`），待链上 E2E/清算演示 ｜ 测试：22 suites / 163 passed（行覆盖：LendingPool 91.8% / LiquidationManager 100% / RiskManager 100%）

---

# 第 1 部分 项目概述

## 1.1 一句话定位

> **ZZZ Lend 是一个以资本效率和风险透明定价为核心的 DeFi 借贷协议，让用户自主选择 LTV 风险档位，并根据真实借款利率、资金利用率、预期损失和协议费用实时计算预估收益。**

核心不是复制 Aave，而是 **"用户自己选择风险，系统实时给风险定价。"**

## 1.2 核心产品理念

- 存款人存入 **USDC** 获得动态预估 **Supply APY**（不构成固定收益承诺）；借款人抵押 **ETH** 借出 USDC。
- **五档 LTV**：50% / 60% / 70% / 75% / 80%；**LTV 越高 → 利率越高 → 风险越高**。
- 80% 是高风险档位，**不是固定收益承诺**。
- 收益动态计算链路：
  - `Gross Yield = Borrow APR × Utilization`
  - `Expected Loss = Default Probability × Loss Given Default`
  - `Estimated Net Yield = Gross Yield − Expected Loss − Protocol Fee`
- 三个收益率分离：**Projected / Current / Realized APY**。
- 必须建立 **Risk Reserve**、**Health Factor**、**Liquidation**、**Stress Test**、**历史数据**。
- 铁律：**不承诺固定收益、不隐藏坏账、公开利用率/储备/清算数据**。

## 1.3 当前阶段状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| 产品/架构设计 | 见本文档第 1.4/2 节（已并入） | ✅ |
| 1 开发环境 | Git + Foundry 1.8.1 + OpenZeppelin v5.7 + lint + Anvil | ✅ |
| 2 业务合约 | LendingPool / 分层 LTV / HF / 清算 / 坏账 / 三套利率预设 | ✅ |
| 2 补充验证 | 压力矩阵 / 重入 / 精度 / 部分还款 | ✅ |
| 4 专项测试 | 以测试形式完成（并入 2/6） | ✅ |
| 6 Oracle + 风险引擎 | ChainlinkOracle / SwitchableOracle / RiskEngine / 坏账即时传导 / minSeize | ✅ |
| 7 Sepolia 部署 | 脚本 + 本地广播验证完成；**链上广播待凭据** | 🔶 |\n| 7.1 安全改进 | ETH转账call / USDC脱锚计价 / 偏差不revert / RiskEngineAuto / 事件补全 / 清算时间差 / 覆盖率 | ✅ 已完成 |
| 7.2 参数与边界 | maxDeviation 默认 30%；异常价禁止新增借款/抵押 | ✅ 已完成 |
| 8 前端 | **Next.js 14 Dashboard 已实现**（Home/Dashboard/Stress Test/History/About，全英文，连接 Sepolia），见 `frontend/README.md` 与 `docs/前端_验证报告_v1.0.md` | ✅ 已完成 |
| 3/5/9/10 | Sepolia E2E 真跑、回测、审计、主网 | ⏳ |

## 1.4 产品设计详解

### 80% LTV 是高风险档
80% 不代表"保证借 80%"，而是"最高风险档位，用户愿意承担更高风险换取更高资本效率"。
80% LTV → 更高风险 → 更高 Borrow APR → 更高潜在 Supply APY。

### 收益率必须实时变化且三分离
- **Projected APY**：模型预测；**Current APY**：当前实时（随利用率/利率/风险变化）；**Realized APY**：真实历史。
- 展示示例：`Borrow APR ~20.00% / Utilization ~80.42% / Gross Yield ~16.08% / Expected Loss ~-1.12% / Protocol Fee ~-1.00% / Estimated Net APY ~13.96%`。
- *以上均为预估收益，随市场利率和资金利用率实时变化，不构成固定收益承诺*。

### 资金流
```
存款人 USDC → LendingPool ─→ 借款人（抵押 ETH 独立记账）
借款利息 → 存款人收益 + 风险储备 + Treasury
```

### 风险储备（Risk Reserve）
利息按**固定费率**分配：存款人 92% / 风险储备 5% / Treasury 3%（合计 100%）。储备目标 = `totalBorrows × 3%`：每次计息后，储备总资产（账面 `totalReserve` + 物理 `ReserveManager` 余额）超过目标的部分自动溢出转入 Treasury（事件 `ReserveOverflowTransferred`）。溢出从**账面 `totalReserve`** 划转；**物理储备（`ReserveManager` 余额）只被坏账消耗，不直接转入 Treasury**（安全设计：储备金只能回注池）。**当 `totalBorrows = 0` 时目标为 0，但**不触发溢出**，储备保留**，待借款恢复后按新目标继续计息。风险储备是**第一损失缓冲**：坏账发生时先由储备覆盖，储备不足部分即时降低 `supplyIndex`，由所有存款人按份额承担（类似基金净值下跌），不挂账、无需核销。Treasury 由 `collectTreasury()`（任何人可调）归集：将 `treasuryAccrued` 全部转给 `treasuryAddress` 并**清零**，`treasuryAddress` 为零地址时 revert。

### 风险来源（不止违约率）
市场、清算（价格急跌来不及清算）、流动性（抵押物无买盘）、Oracle（异常/延迟）、智能合约、坏账、收益率（利用率下降）、极端行情（ETH -30%~-50%）。

### Health Factor 状态灯
🟢 Healthy / 🟡 Warning / 🟠 High Risk / 🔴 Liquidation（HF<1）。

### 压力测试（已实现为 StressTest）
用户可模拟 ETH -10/-20/-30/-40/-50%，查看 LTV/HF/是否清算。

### 动态风险引擎
LTV 档位可随市场调整（正常/高波动/极端三套预设；极端暂停高 LTV 档）。

### 用户界面（规划）
首页展示 Total Supply / Borrow / Utilization / TVL / Supply APY / Borrow APR / Risk Reserve，并提供 **Choose Your Risk** 五档选择。

### ZZZ vs Aave
| Aave 类传统 | ZZZ Lend |
|---|---|
| 固定风险参数 | **风险分层** |
| 只看利率 | **同时看风险** |
| LTV 是参数 | **LTV 是用户选择** |
| APY | **Projected/Current/Realized** |
| 风险信息专业 | **风险可视化** |

### 赚钱方式
① Borrow Spread（借款人付 20%、存款人拿 ~14%，差价=协议收入）② Protocol Fee（利息一定比例进 Treasury）③ 未来：清算费/Vault/机构借贷。

### 项目原则
不承诺固定收益、不隐藏坏账、不只展示 APY、公开利用率/历史表现/风险储备/清算数据、让用户看到最坏情况。

### 核心公式
`Gross Yield = Borrow APR × Utilization`；`Expected Loss = PD × LGD`；`Net = Gross − Expected Loss − Protocol Fee`。

---

## 1.5 收益展示规范（强制）

### 1.5.1 核心原则

- 所有档位（50% / 60% / 70% / 75% / 80%）的收益均为预估，**没有任何一档是固定收益**。
- 高 LTV 档**不是**"高收益固定产品"，而是"**高风险、高潜在收益、高波动**"的档位。
- 低 LTV 档也**不是**"保本理财"，同样存在坏账风险和收益率波动。
- 任何收益数字前必须加"预估 / 预计 / ~"，首次出现 APY 必须标注"不构成固定收益承诺"。
- 存款本金可能因坏账而受损：坏账超出风险储备缓冲的部分由存款人按份额承担（`supplyIndex` 即时下降），类似基金净值下跌。

### 1.5.2 前端展示规范（阶段 8 必须遵守）

每个 LTV 档位卡片**必须**包含：

1. 档位名称和 LTV 数值（如 `Tier 5 · LTV 80%`）
2. **预估 APY**（数字前必须有"~"，如 `~13.96%`）
3. 收益拆解入口（点击展开显示 `Gross Yield / Expected Loss / Protocol Fee / Reserve`）
4. 风险等级标签（低 / 中 / 较高 / 高 / 极高）
5. 每档标注 **"Estimated, not guaranteed"**
6. 底部小字：`*预估收益，随市场利率和资金利用率实时变化，不构成固定收益承诺*`

#### 示例卡片

```
┌────────────────────────────────────────────┐
│  Tier 5 · LTV 80%                 [风险 极高] │
│  预估 APY: ~13.96%                          │
│  ─────────────────────────────────────────  │
│  ▼ 收益拆解（点击展开）                      │
│     Gross Yield      ~16.08%                │
│     Expected Loss    ~-1.12%                │
│     Protocol Fee     ~-1.00%                │
│     Reserve          ~-0.00%                │
│  ─────────────────────────────────────────  │
│  *预估收益，随市场利率和资金利用率实时变化，   │
│   不构成固定收益承诺*                        │
└────────────────────────────────────────────┘
```

---

## 1.6 前端界面与风险披露规范（强制·阶段 8 必须遵守）— v1.0 · 2026-09-01（已按本规范实现，见 `frontend/`）

1. **前端界面全部使用英文**，不出现中文宣传性文案。
2. **存款页面**必须显著展示风险提示：
   > "Deposits are not guaranteed. Your principal may decrease due to bad debt, similar to a fund whose NAV can decline."
3. **取款页面**展示当前可用流动性：
   > "Available Liquidity: $XX,XXX. Withdrawals may fail if pool liquidity is insufficient."
4. **首页**展示历史最大回撤（Max Drawdown）：
   > "Historical Max Drawdown: X.X%"
5. **所有 APY 数字标注 "Estimated"**，禁止使用 "Guaranteed" / "Fixed" / "Stable" 等表述。
6. 收益拆解展示：`Gross Yield / Expected Loss / Protocol Fee / Reserve`。
7. **五档 LTV 卡片每档标注 "Estimated, not guaranteed"**。
8. 每个 LTV 档位卡片遵循 §1.5.2 的展示规范（含预估 APY、收益拆解、风险标签、底部小字）。

---

# 第 2 部分 系统架构与技术选型

## 2.1 分层架构

```
用户/前端（Next.js 已实现）                数据服务（规划）
   │  viem/wagmi                    │  REST/WS
   ▼                                ▼
Wallet (EIP-1193)          ZZZ Backend（风险展示/历史/建议）
   │  tx                            │
   ▼                                ▼
┌────────────── 链上 (Sepolia) ──────────────┐
│ LendingPool（存/借/清算/坏账/储备）           │
│   ├─ InterestRateModel（利率+预设）          │
│   ├─ RiskManager（LTV档/清算参数）           │
│   ├─ LiquidationManager（清算数量）          │
│   ├─ ReserveManager（风险储备）             │
│   ├─ ChainlinkOracle（价格，含安全机制）      │
│   └─ RiskEngine（风险等级+波动率，只建议不执行）│
└──────────────┬──────────────────────────┘
               │ Chainlink Aggregator (ETH/USD, USDC/USD)
```

## 2.2 技术选型

| 领域 | 选型 |
|---|---|
| 合约框架 | Foundry 1.8.1（forge/anvil/cast） |
| 依赖 | OpenZeppelin Contracts v5.7.0、forge-std |
| Solidity | 0.8.24 / EVM cancun / optimizer 200 runs / via_ir |
| Oracle | Chainlink（ETH/USD、USDC/USD），带 stale/deviation/fallback/pause |
| 前端 | Next.js 14 + TypeScript + viem/wagmi + Tailwind（**已实现**，`frontend/`，连接 Sepolia） |
| 数据层 | The Graph Subgraph（规划）；`services/` 已预留 |
| 测试链 | Anvil（本地）/ Sepolia（测试网） |

---

# 第 3 部分 合约模块详解

## 3.1 合约清单（`contracts/src/`）— v1.0 · 2026-08-31

| 合约 | 作用 | 是否持资金 |
|---|---|---|
| `LendingPool.sol` | 主合约：supply/withdraw、抵押/取回 ETH、borrow/repay、liquidate、handleBadDebt、skimReserve、accrue、collectTreasury、固定费率分配 + 储备溢出转Treasury、份额记账+分层指数计息、HF、暂停 | ✅ USDC+ETH |
| `InterestRateModel.sol` | Utilization→Borrow APR（base+两段斜率+kink+每档溢价）；**三套市场预设** NORMAL/HIGH_VOL/EXTREME | ❌ |
| `RiskManager.sol` | 五档 LTV(50/60/70/75/80%)、清算阈值(60/70/78/85/90%)、bonus 5%、close factor 50%、maxBorrowTier、validateBorrow、HF | ❌ |
| `LiquidationManager.sol` | 清算没收量计算（bonus 封顶抵押总额） | ❌ |
| `ReserveManager.sol` | 持有风险储备 USDC，仅可向池注资（坏账兜底），无任意取款 | ✅ 储备 |
| `oracle/ChainlinkOracle.sol` | Chainlink 适配器：8 位小数、freshness/deviation/fallback/pause | ❌ |
| `oracle/SwitchableOracle.sol` | 可切换预言机：主源=Chainlink；PAUSER 切到"管理员可设价"模式做清算测试，PAUSER 切回 | ❌ |
| `risk/RiskEngine.sol` | 风险等级（LOW/MED/HIGH/EXTREME）+ 波动率采样 + 阈值（带上下限），**只输出建议** | ❌ |
| `interfaces/IPriceOracle.sol` | 价格接口（无缝替换 Mock/Chainlink） | — |
| `mocks/` | MockUSDC、MockPriceOracle、MockAggregatorV3（测试/演示用） | — |

## 3.2 关键参数默认值 — v1.0 · 2026-08-31（参数变更后更新本表日期）

**五档 LTV / 清算阈值**（v1.0 · 2026-08-31）
| 档 | 最大 LTV | 清算阈值 | 利率溢价(t1..t5 基础之上) | 预估收益特征 |
|---|---|---|---|---|
| 1 🟢 | 50% | 60% | 0 | 预估，不承诺固定收益 |
| 2 🟡 | 60% | 70% | +0.5% | 预估，不承诺固定收益 |
| 3 🟠 | 70% | 78% | +1.5% | 预估，不承诺固定收益 |
| 4 🔴 | 75% | 85% | +3% | 预估，不承诺固定收益 |
| 5 🔴 | 80% | 90% | +6% | 预估，不承诺固定收益 |

**三套利率预设**（NORMAL / HIGH_VOL / EXTREME，v1.0 · 2026-08-31）
| 预设 | base | slope1 | kink | slope2 | 溢价(t1..t5) | 高LTV档 |
|---|---|---|---|---|---|---|
| NORMAL | 2% | 8% | 80% | 60% | 0/0.5/1.5/3/6% | 开放 |
| HIGH_VOL | 2% | 20% | 65% | 150% | 0/1/3/5/8% | 开放 |
| EXTREME | 5% | 40% | 50% | 300% | 0/2/5/8/12% | **tier4/5 暂停** |

**ChainlinkOracle 安全阈值**（v1.0 · 2026-08-31）
| 参数 | 默认 | 范围 |
|---|---|---|
| maxStaleness | 3600s(1h) | 300s~7天 |
| maxDeviation | 30% | 10%~200% |
| fallbackMaxAge | 86400s(1天) | 1h~30天 |
| pause 行为 | revert "oracle paused" | — |

**RiskEngine 判定阈值**（四因子取最高档，v1.0 · 2026-08-31）
| 因子 | LOW | MEDIUM | HIGH | EXTREME |
|---|---|---|---|---|
| 年化波动率 | <30% | 30-60% | 60-100% | ≥100% |
| Utilization | <50% | 50-75% | 75-90% | ≥90% |
| LTV/LT 比值 | <0.6 | 0.6-0.8 | 0.8-1.0 | ≥1.0 |
| 流动性 | ≥25% | ≥10% | ≥1% | <1% |

**池参数**（v1.2 · 2026-08-31）：固定费率（存款人 92% / 储备 `reserveFactor=5%` / Treasury `treasuryFactor=3%`）、储备目标 `reserveTargetRatio=3%`（超出自动溢出转 Treasury）、清算 bonus=5%、close factor=50%、supplyIndex 起始 1e18、**最小金额限制（dust limit）**：`MIN_SUPPLY=10 USDC`、`MIN_BORROW=100 USDC`、`MIN_COLLATERAL=0.01 ETH`。

## 3.3 资金流与不变式 — v1.0 · 2026-08-31

- 资金流：存款人 USDC → 池 → 借款人；借款人 ETH → 抵押（独立记账）；利息 → 存款人 92% + 风险储备 5% + Treasury 3%。
- **核心不变式**：`cash + totalBorrows == getTotalSupply() + totalReserve + treasuryAccrued`（每笔操作后测试断言）。
- 坏账（即时传导）：抵押归零仍有债 → `handleBadDebt`（任何人可调）先由风险储备（第一损失缓冲）覆盖可覆盖部分，未覆盖部分即时降低 `supplyIndex`，由所有存款人按份额承担损失；仓位一次性清零，**不挂账、无 `settleBadDebt`**。事件 `BadDebtRealized(user, badDebtAmount, coveredByReserve, lossToDepositors, oldSupplyIndex, newSupplyIndex)`。
- 储备溢出：每次计息后，储备总资产（账面 + 物理）超过 `totalBorrows × 3%` 的部分溢出转 Treasury（事件 `ReserveOverflowTransferred`）；溢出只从**账面 `totalReserve`** 划转，物理储备仅由坏账消耗；`totalBorrows = 0` 时不触发溢出，储备保留。
- 清算：HF<1 可清算，close factor 50%，清算人按 105% 估值没收 ETH；`liquidate(...,minSeizeAmount)` 支持最低没收量（0=不限）。

## 3.4 权限模型 — v1.0 · 2026-08-31

- LendingPool / ChainlinkOracle / RiskEngine：AccessControl 三角色（DEFAULT_ADMIN / PARAM_ADMIN / PAUSER，PAUSER 仅前两者有）。
- InterestRateModel / RiskManager / ReserveManager：Ownable。
- 管理员能：改参数/换模块地址/暂停/切预设；**不能**：动用户存款/抵押、绕过 LTV/HF/清算规则、注入任意价格、直接降低 `supplyIndex`（只能经 `handleBadDebt` 触发）、RiskEngine 不触碰资金。
- 风险引擎：只输出风险等级与建议，参数调整必须 PARAM_ADMIN/PAUSER 手动执行。

---

# 第 4 部分 测试体系与结果

## 4.1 测试总览 — 2026-08-31（每次跑完测试更新本表日期/用例数）

```
forge test:  22 suites, 163 passed, 0 failed, 0 skipped
forge fmt --check: 通过 ｜ npm run lint: 0 errors（369 warnings，风格性）
```

| 测试文件 | 用例 | 覆盖 |
|---|---|---|
| LendingPool.t.sol | 14 | 存取/借贷/档位LTV/tier锁定/还款/利息/比例分配/利用率/流动性限制/HF |
| InterestRateModel.t.sol | 7 | 利率曲线/kink/档位溢价/权限/边界 |
| RiskManager.t.sol | 6 | 默认档位/LTV校验/HF/权限/边界 |
| Liquidation.t.sol | 7 | 健康不可清算/价格下跌清算/close factor/禁自清算/坏账兜底 |
| ReserveManager.t.sol | 7 | 储备分成/skim/仅池可调用/零地址/无任意取款 |
| Permissions.t.sol | 8 | 角色隔离/暂停语义/管理员不可挪用 |
| StressTest.t.sol | 1(30场景) | 6跌幅×5档：HF、清算时机、坏账、资金守恒、储备兜底 |
| Security.t.sol | 3 | borrow/withdraw/liquidate 重入被 Guard 拦截 |
| Precision.t.sol | 6 | 1微USDC存取/借贷/清算、向上取整、部分取款不超 |
| Repay.t.sol | 5 | 多次小额还款/档位锁定/超额封顶/复利正确 |
| RatePresets.t.sol | 6 | 三套预设曲线/切换权限/EXTREME暂停高LTV档 |
| Oracle.t.sol | 11 | 正常读取/stale/偏差事件化+29/31%边界/fallback+pause/参数权限/removeFeed/异常价禁借+清正常 |
| SwitchableOracle.t.sol | 7 | 默认走主源/切换可设价/设价权限/切回主源/PAUSER切换/暂停/与LendingPool清算集成 |
| RiskEngine.t.sol | 12 | 四级判定/波动率精度/不触碰资金/阈值边界/非法liquidity/calculateRiskLevelAuto |
| EthTransfer.t.sol | 3 | 合约收款不失败/清算转ETH给合约/重入仍被Guard拦截 |
| UsdcPeg.t.sol | 5 | USDC=1一致/溢价抬LTV降HF/脱锚降LTV抬HF/溢价触发清算/零价revert |
| Events.t.sol | 6 | Borrowed/Repaid/Liquidated/InterestAccrued/BadDebtRealized/OracleSwitched 事件参数 |
| LiquidationTimeGap.t.sol | 1(9场景) | 1h/6h/24h × 续跌5/10/20%：利息累计/坏账扩大/守恒 |
| BadDebt.t.sol | 9 | 坏账即时传导：储备充足 supplyIndex 不变 / 储备不足与为零时降 supplyIndex / 多存款人等比例受损 / 坏账后取款与利息累计 / 管理员不可直改 supplyIndex / 零坏账无状态变化 / BadDebtRealized 事件 |
| SecurityFixes.t.sol | 20 | 审计 v1.1 修复回归（F1 取整下溢 / F3 setPrice 校验 / F4 零地址 / F2 超额损失守恒 / F5 实时偏差 / F9 oracle 暂停清算）+ v1.2 最小金额限制（MIN_SUPPLY/MIN_BORROW/MIN_COLLATERAL） |
| FeeMechanism.t.sol | 12 | 固定费率 92/5/3 合计100%；储备未达标无溢出/达标溢出转Treasury/恰达目标新增5%全溢出/坏账消耗储备后溢出停止/借款增减改变目标/totalBorrows=0 不溢出储备保留/collectTreasury 转账与零地址revert/溢出事件/参数边界 |
| MinSeize.t.sol | 3 | minSeize 通过/不足 revert/0 不限制 |

## 4.2 压力测试汇总（`contracts/test-out/stress_matrix.md` 自动生成）— 2026-08-31

| 跌幅 | T1(50) | T2(60) | T3(70) | T4(75) | T5(80) |
|---|---|---|---|---|---|
| -5%/-10% | 不触发清算/守恒 | 同左 | 同左 | 同左 | 同左 |
| -20% | 清算/守恒 | 清算/守恒 | 清算/守恒 | 清算/守恒 | 清算/**坏账**/守恒(储备兜底) |
| -30% | 清算/守恒 | 清算/守恒 | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** |
| -40% | 清算/守恒 | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** |
| -50% | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** | 清算/**坏账** |

清算时机与独立计算的 HF<1 完全一致；所有场景资金守恒；坏账场景由储备部分兜底 + 存款人按份额承担。

## 4.3 部署与 E2E 本地验证 — v1.0 · 2026-08-31（Sepolia 真网 E2E 见 `docs/E2E_Sepolia_测试报告.md`）

- 部署脚本 `script/Deploy.s.sol` 在 Anvil 真实广播成功（合约、角色、接线、JSON 正确）。
- E2E `script/e2e_sepolia.sh` 在 Anvil 全 8 步 status=0x1：
  A 存 1000 → deployer 补流动性 → B 存 10 ETH → B 借 21000@tier3（HF=1.114）→ 状态检查 → B 部分还款 → A 提取一半 → **Mock 价跌 30% 清算（HF 0.867→0.914）** → 资金守恒（差 1 尘埃）。

---

# 第 5 部分 安全模型与风险

## 5.1 已实现的安全机制

- ReentrancyGuard（全部状态函数）；ETH 转账用 `call{value}`（`_safeSendEth`，失败 revert），不受 2300 gas 限制，重入仍被 Guard 拦截。
- CEI：事件前置、状态先更新再外部调用。
- 份额记账 + 逐档指数计息；**全部金额向上/向下取整方向对协议有利**。
- **USDC 脱锚计价**：债务美元价值 = USDC 数量 × USDC/USD 价格（LTV/HF/可借额随之正确变化），资金守恒不变式不受影响。
- **Oracle 偏差不阻塞清算**：偏差过大不 revert，返回新价格并触发 `PriceAnomalyDetected`（maxDeviation 默认 **30%**，范围 10%~200%）；PAUSER 可暂停。
- **异常价禁止新增敞口**：价格被标记异常时，`borrow` 与 `supplyCollateral` revert（`"price anomalous"`）；`repay`/`withdraw`/`liquidate` 正常，保证能退出与清算。
- 暂停开关（暂停时仅允许取款/还款/清算）。
- Oracle：stale 仍 revert、偏差事件化、fallback 时限、pause；管理员无法注入任意价格。
- 管理员无法挪用用户资金（测试断言）。
- 关键状态变更均有事件（Borrowed/Repaid/Liquidated 含 LTV·HF·剩余债务·postHF；InterestAccrued；BadDebtRealized；OracleSwitched；PriceAnomalyDetected）。
- **坏账即时传导给存款人**：坏账超出风险储备（第一损失缓冲）的部分会即时降低 `supplyIndex`，所有存款人按份额承担，**存款本金可能受损**。
- **储备溢出自动转 Treasury**：储备总资产超过 `totalBorrows × 3%` 的部分自动转入 Treasury（`ReserveOverflowTransferred`），储备不会无限膨胀；溢出只从账面 `totalReserve` 划转（物理储备仅由坏账消耗），`totalBorrows = 0` 时不触发溢出。
- 所有收益均为预估，随市场利率和资金利用率实时变化，协议不承诺固定收益。

## 5.2 当前风险与待办 — v1.0 · 2026-08-31

| 风险 | 说明 | 缓解/待办 |
|---|---|---|
| 管理员集中 | 部署者持 DEFAULT_ADMIN + 多余 PARAM_ADMIN/PAUSER（未撤销） | 生产移交多签、撤销部署者 |
| Oracle 单点 | setFeed 可换价格源地址 | 生产多签；审计 |
| 风险引擎建议不自动执行 | 依赖管理员及时响应 | 前端监控告警 |
| 偏差容忍的副作用 | 极端跳价会以异常价执行（为保清算） | 事件监控 + PAUSER 暂停兜底 |
| liquidity 无挂钩 | RiskEngine 手动参数可被伪造；`calculateRiskLevelAuto` 从池直读（已有 0~1 校验） | 前端展示用 Auto |
| lint 风格 | 369 warnings（require→custom errors 等） | 后续优化 |
| 未经外部审计 | — | 阶段 8 审计 |

---

# 第 6 部分 部署指南（Sepolia）

## 6.1 前置

```bash
# .env（已 gitignore）至少含：
SEPOLIA_RPC_URL=...            # Alchemy/Infura
PRIVATE_KEY=0x...              # 测试网专用，cast wallet new 生成，绝不用主网
ETHERSCAN_API_KEY=...
SEPOLIA_ETH_USD_FEED=0x694AA1769357215DE4FAC081bf1f309aDC325306
SEPOLIA_USDC_USD_FEED=0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E
TESTNET_ADMIN=0x...            # 可选，缺省=部署者
E2E_USER_A_KEY / E2E_USER_B_KEY # E2E 用户私钥（测试网）
```

## 6.2 部署

```bash
forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
```
- 部署顺序：MockUSDC → ChainlinkOracle(+MockPriceOracle) → InterestRateModel → RiskManager → LiquidationManager → ReserveManager → RiskEngine → LendingPool → 初始化接线 → 角色移交。
- 地址写入 `deployments/sepolia.json`。

## 6.3 验证

```bash
forge script script/Verify.s.sol:Verify --rpc-url $SEPOLIA_RPC_URL
# 或逐合约：forge verify-contract <addr> LendingPool --chain 11155111 --compiler-version v0.8.24 --etherscan-api-key $ETHERSCAN_API_KEY --watch
```

## 6.4 E2E

```bash
bash script/e2e_sepolia.sh   # cast 逐笔，已本地验证（Anvil 全 8 步 status=0x1）
```

## 6.5 清算测试方案（关键）— v1.0 · 2026-08-31

- 真实 Chainlink 无法操纵 → 部署时 LendingPool 价格源 = **SwitchableOracle**（主源=Chainlink）。
- 测试流程：**PAUSER** `SwitchableOracle.enableSettable()` → **PARAM_ADMIN** `SwitchableOracle.setPrice(ETH, 2100e8)`（-30%）→ `LendingPool.liquidate(...)` → **PAUSER** `SwitchableOracle.disableSettable()` 切回主源。
- 已在 Anvil 真实广播验证（HF 1.114→0.867→清算→0.914，守恒精确相等）。

| 动作 | 合约 | 函数 | 权限 |
|---|---|---|---|
| 切换到可设价模式 | SwitchableOracle | `enableSettable()` | PAUSER |
| 设价（-30% → 2100e8） | SwitchableOracle | `setPrice(address,uint256)` | PARAM_ADMIN |
| 执行清算 | LendingPool | `liquidate(address,uint256,uint256)` | 无 |
| 切回主源（必须执行） | SwitchableOracle | `disableSettable()` | PAUSER |
| 紧急暂停读价 | SwitchableOracle | `pause()`/`unpause()` | PAUSER |

## 6.6 角色矩阵（部署后回填实际地址）— v1.0 · 2026-08-31

| 合约 | PARAM_ADMIN | PAUSER | DEFAULT_ADMIN / Owner |
|---|---|---|---|
| SwitchableOracle / LendingPool / ChainlinkOracle | 部署者 + TESTNET_ADMIN | 部署者 + TESTNET_ADMIN | **仅部署者** |
| RiskEngine | 部署者 + TESTNET_ADMIN | — | **仅部署者** |
| InterestRateModel / RiskManager / ReserveManager | — | — | Owner = TESTNET_ADMIN |

> **部署者始终是最终管理者**（DEFAULT_ADMIN 未移交 + 未撤销构造器角色）。测试网可接受；生产必须移交多签并撤销部署者角色。TESTNET_ADMIN 缺省=部署者。

## 6.7 已部署地址回填表（Sepolia · 2026-08-31 · v1.0）

| 合约 | 地址 | 验证状态 |
|---|---|---|
| MockUSDC | `0x3b661C85cAC1eEfE87dA365c43498A0166399D5D` | ✅ 已部署 |
| ChainlinkOracle | `0xb89ddB72c1F97b0C1CcbF5f842d029856Aff979c` | ✅ 已验证（ETH/USD 实时可读） |
| SwitchableOracle | `0x33e6974B61dA455a97482BfF05EFb8191a447007` | ✅ 已验证（主源=Chainlink） |
| MockPriceOracle | `0x83DadF7A57908D06B54969A1587fc4D4F5b7f4D7` | ✅ 已部署 |
| InterestRateModel | `0xad3f7eee666DAEE83AcaBb625DD66ed7E402002b` | ✅ 已验证（NORMAL 预设） |
| RiskManager | `0xad07d4918923Cb62df85F1F16d2630A5CECa2bB6` | ✅ 已部署 |
| LiquidationManager | `0xa672e6fE327317E7c76C4335db78243dC81FB2c9` | ✅ 已部署 |
| ReserveManager | `0xf42745f887f8a469A61C18eC765244Fe917Df634` | ✅ 已验证（lendingPool 接线正确） |
| RiskEngine | `0xB203c077EB69B99954846Fb9521D1D56E6F5764C` | ✅ 已部署 |
| LendingPool | `0x4c0F60fb5ee400f8430259a8C20cB35dE31d1a19` | ✅ 已验证（参数/角色/费率） |

> **部署记录（2026-08-31）**：RPC 用 `https://ethereum-sepolia-rpc.publicnode.com`（ankr 需 API key、`rpc.sepolia.org` 404）。部署者 `0xC35C...6830`（4 ETH 起，部署后 ~3.988 ETH）。LendingPool 参数验证：`getUtilization()=0`、`getSupplyAPR()=0`、`getBorrowAPR(1)=~2%`、`reserveFactor=5%`、`treasuryFactor=3%`、`reserveTargetRatio=3%`、`supplyIndex=1e18`；角色 DEFAULT_ADMIN/PARAM_ADMIN/PAUSER=部署者；`ReserveManager.lendingPool` 已接线。⚠️ **USDC/USD feed（`0xA2F78...`）当前 stale**：last update ~11h 前，超过 1h `maxStaleness`，读 USDC 价会 revert（价格本身正确 0.9999）；待 feed 更新或由管理员调 `maxStaleness` 后再做借/还/清算相关操作。**E2E 已执行**（存/借/还/取/清算/守恒全通过，金额因测试网 ETH 余额缩放），详细报告见 `docs/E2E_Sepolia_测试报告.md`。

## 6.8 cast 命令速查

```bash
# 部署（写 deployments/sepolia.json；--verify 需 ETHERSCAN_API_KEY）
forge script script/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast --verify -vvvv
# 本地逻辑验证（MOCK_FEEDS=1 部署模拟聚合器）
MOCK_FEEDS=1 forge script script/Deploy.s.sol:Deploy --rpc-url http://127.0.0.1:8545 --broadcast
# 验证合约
forge script script/Verify.s.sol:Verify --rpc-url $SEPOLIA_RPC_URL
# 手动操作
cast send $POOL "supply(uint256)" 1000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $USER_A_KEY
cast call $POOL "getUserHealthFactor(address)(uint256)" $USER_B --rpc-url $SEPOLIA_RPC_URL
# 测试币：ETH faucet（sepoliafaucet.com / faucets.chain.link）；MockUSDC 直接 faucet()
cast send $USDC "faucet(uint256)" 1000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $USER_A_KEY
```

## 6.9 常见错误排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `InsufficientFunds` | 钱包无测试网 ETH | 先领 faucet |
| `nonce too low` | 并发交易 | 等确认或指定 `--nonce` |
| `stale price` / `price deviation` | Chainlink 未更新/价格跳变 | 等喂价或检查 feed |
| `insufficient liquidity` | 池内现金不足 | 增加存款 |
| `ltv too high` | 借款超档位上限 | 用 `maxBorrowable` |
| `oracle paused` | 预言机被 PAUSER 暂停 | `unpause()` |
| `tier locked` | 已有借款档位 | 先还清再换档 |
| `price not set` | SwitchableOracle 可设价模式下未设价 | 先 `setPrice` |
| 验证失败 | 少 compiler-version | 加 `--compiler-version v0.8.24` |

## 6.10 安全红线

- ❌ 不使用主网 RPC / 主网钱包 / 真实 USDC。
- ❌ 私钥只存 `.env`（已 gitignore），不进 git。
- ❌ 不得在任何宣传材料中使用"固定收益""保本保息"等表述。
- ❌ 不得宣传"保本""本金安全""刚兑""固定收益"等表述（存款本金可能因坏账而受损）。
- ✅ 全部测试网资产，可随时作废重建。
- ✅ 清算演示后必须 `disableSettable()` 切回真实 Chainlink。

---

# 第 7 部分 设计确认 Q&A（关键决策记录）

1. **ETH 抵押品**：原生 ETH；转账用 `call{value}`（`_safeSendEth`），失败 revert；不受 2300 gas 限制；重入仍被 ReentrancyGuard 拦截。
2. **ReentrancyGuard**：全部状态函数已加。
3. **minAmount 滑点**：V1 无 AMM 无滑点；清算已加 `minSeizeAmount`（0=不限）。
4. **70%→78% 清算阈值（缓冲 8%）**：有意设计，参数可配。
5. **USDC/USD**：债务美元价值 = USDC 数量 × USDC/USD Chainlink 价格；USDC=1 时行为与之前完全一致；USDC 溢价（>1）抬升 LTV、降低 Health Factor；USDC 脱锚（<1）降低 LTV、抬升 Health Factor；UsdcPeg.t.sol 已覆盖 5 个场景。
6. **RiskEngine**：纯建议；任何人可调 `getRiskLevel`；liquidity 有 0~1 校验。
7. **无绕过 oracle 校验的读价路径**。

---

# 第 8 部分 路线图与待办

## 8.1 待办

1. **Sepolia 真部署**（待凭据：RPC/测试币/私钥/Etherscan Key），回填本文档 6.7 地址表。
2. ✅ 前端 Dashboard（Next.js 已实现：Home/Dashboard/Stress Test/History/About，全英文，见 `frontend/README.md` 与 `docs/前端_验证报告_v1.0.md`）。
3. 数据服务（`services/`）+ Subgraph。
4. 生产权限收口（多签/撤销部署者）、外部安全审计。
5. Git 首次提交（当前 `git init` 未提交、未配 user.name/email）。

## 8.2 完整路线（总纲）

产品设计 → 合约骨架 → Sepolia 全流程 → 回测/压力 → 前端 → 安全审计 → 小规模真实资金（主网后）。

---

*本文档为项目唯一总文档（原分阶段文档已并入后删除）。*
