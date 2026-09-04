# ZZZ Lend

风险分层 DeFi 借贷协议（Base 主网 / Sepolia 测试网）。

## 简介

ZZZ Lend 是一个模块化的借贷协议：用户可存入 **USDC / USDT / DAI** 赚取利息，并以 **ETH / cbBTC**（Base V1）作为抵押品借款。协议通过 **风险分层（5 档 LTV/LT）** 精细控制风险，内置清算、坏账处理、储备金与 Treasury 分成机制。

> ⚠️ **状态声明**：协议已完成 Sepolia 测试网验证（230 项测试全绿）与 Base 主网 fork dress rehearsal，**但尚未经过外部安全审计**。在主网上线前请自行评估风险，或联系专业审计机构。

## 核心特性

- **多资产市场**：USDC（基座）、USDT、DAI 借贷市场 × ETH、cbBTC 抵押品（wstETH 合约支持保留，Base V1 因无官方 feed 默认禁用）
- **风险分层**：每抵押品 5 档 LTV/Liquidation Threshold（cbBTC 保守档 45/55/65/70/75，ETH 档 50/60/70/75/80），借款按 tier 计息
- **供应/抵押上限**：`setMarketSupplyCap` / `setCollateralCap` 每市场/每抵押品总量上限（0 = 不限制）
- **清算与坏账**：抵押品清算、`handleBadDebt` 坏账处理（先扣储备，后摊薄存款人）
- **收益分配**：借款人利息 → 存款人 94% / 储备 4% / Treasury 2%（可治理调整）
- **治理**：可选 OZ TimelockController 包裹（参数变更走延迟执行）；PAUSER 独立即时熔断；多签（Safe）权限收口
- **Oracle**：Chainlink 喂价，部署前 `_preflight` 校验 feed decimals / 价格 / 新鲜度

## 架构

```
contracts/
├── src/
│   ├── LendingPool.sol          # 核心：存取借还、清算、caps、Treasury
│   ├── RiskManager.sol          # LTV / LT 风险档位
│   ├── LiquidationManager.sol   # 清算折扣 / bonus
│   ├── ReserveManager.sol       # 储备金
│   ├── InterestRateModel.sol    # 利率模型（NORMAL 预设）
│   ├── oracle/ChainlinkOracle.sol
│   └── risk/RiskEngine.sol      # 风险评估与采样
├── script/
│   ├── DeployMainnet.s.sol      # Base 主网部署模板（Base 官方 token/feed 内建）
│   └── MainnetDeployAndTransfer.s.sol # 多签/Timelock 权限收口（Step 4–11）
├── test/                        # forge test 32 suites / 230 passed
└── deployments/                 # 部署产物（gitignored）
frontend/       # Next.js 前端（zzz-lend.pages.dev/dashboard）
services/monitor/ # 轮询监控（可清算 / 低 HF / 利用率 / feed 告警，Telegram/webhook）
scripts/feed-health-check/ # Base feed 健康检查（TS+viem）
docs/           # 完整文档 / 审计报告 / 主网准备手册
```

## 快速开始（合约）

```bash
cd contracts
cp .env.example .env   # 填 RPC / 私钥
forge build
forge test             # 全量测试（ForkMainnet 仅在 Base fork 下运行）
# Base 主网 fork dress rehearsal：
forge test --match-contract ForkMainnet -vvv --fork-url https://mainnet.base.org
```

## 主网部署（Base · chainId 8453）

1. 创建 Safe 多签（官方地址已在 `docs/主网多签与权限收口手册.md` 核验）
2. `forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url ... --broadcast`
3. `forge script script/MainnetDeployAndTransfer.s.sol:MainnetDeployAndTransfer --rpc-url ... --broadcast`（权限收口）
4. 链上人工复核（脚本 Step 10/11）

> 部署前请在 fork 上 dry-run 预演；权限收口脚本**不做部署**，只做角色移交与撤销。

## 文档

- `docs/ZZZ_Lend_完整文档.md` — 协议完整说明
- `docs/主网Oracle配置表.md` / `docs/主网多签与权限收口手册.md` / `docs/冷启动与运营方案.md` — Base 主网上线准备
- `docs/Fork主网dress rehearsal报告.md` — Base fork 演练结果（8/8）
- `docs/安全审计报告_V2多资产_2026-09-02.md` — 内部审计

## License

[MIT](LICENSE) © 2026 xzzz0371-maker

允许任何人自由使用、修改、商用，**但请保留本项目来源与本版权声明**。
