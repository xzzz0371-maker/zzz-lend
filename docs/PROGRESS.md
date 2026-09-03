# ZZZ Lend — 项目进度总览（PROGRESS）

> 更新：2026-09-03 ｜ 仓库：https://github.com/xzzz0371-maker/zzz-lend （main）
> 定位：风险分层 DeFi 借贷（测试网 Sepolia V2 多资产）；**尚处主网准备期，未上主网**。
> 关联：`docs/ZZZ_Lend_完整文档.md`、`docs/安全审计报告_V2多资产_2026-09-02.md`、`docs/主网准备_本轮改动说明与遗留问题_2026-09-03.md`、`docs/任务记录.md`（本机）。

---

## 1. 当前状态（一句话）
代码/测试层已到“可自闭环的主网准备就绪”，并已 5 次整组部署到 Sepolia（最新池带正确 D1 顺序）；**上主网仍有外部/治理前置项未完成（见 §4），当前不建议上主网**。本轮（§3.1）两项本环境可继续事项已完成：主网就绪部署模板脚本 + 四组补强测试。

### 关键基线
- 合约测试：**29 suites / 215 passed / 0 failed**（新增 26：定向 fuzz 7、极值矩阵 4、坏账 front-run 快照 4、addMarket/admin 分支 11）
- 工具：`forge test --fuzz-runs 5000` 通过；状态机不变式 4/4；Slither 39 合约/102 检测器 **0 findings**；coverage：LendingPool 行 ~93.97%
- 合约尺寸：LendingPool ~20.6–21.4KB（< EIP-170 24576）
- 前端：`npm run build` 通过，Cloudflare Pages 在线（静态导出，连 Sepolia 当前池）

---

## 2. 已完成工作

### 2.1 V2 多资产架构（合约）
- 单池多市场：USDC/USDT/DAI 借贷市场 × ETH/wstETH/WBTC 抵押；每市场独立现金/供应指数/利用率/利率/储备/Treasury/坏账
- 精度全参数化（wadScale；6/8/18 位）；跨抵押品加权 LTV/LT 健康度；跨市场同 tier 借款；任意市场×任意抵押品清算；全局 tier（首借锁定）
- RiskManager 按抵押资产×档位（ETH/wstETH 同表，WBTC 保守表）；ReserveManager 按 token；InterestRateModel NORMAL 三段曲线（kink1 80%/kink2 85%/slope2a 25%）
- 为过 EIP-170 做了压缩：移除用户事件、合并 `marketAccounts` 视图、精简 V1 包装（存量测试改为 market0 显式入参）

### 2.2 代码修复（审计与实测发现，均已进测试/主网前代码）
- **D1（审计 High）坏账吸收顺序**：最终正确顺序 = 物理储备 → 账面储备 → 存款人(supplyIndex) → **Treasury 最后兜底**；已按此修正并第 5 次上链
- **全额还款一次清零**：`repay ≥ 债务` 时整笔清零，消除 floor 取整尘埃
- **SafeERC20**：LendingPool/ReserveManager 全部 ERC20 转账改为 safe 版（兼容无返回值 token）
- 跨市场坏账时保留全局 tier（早期缺陷修复 + 回归）
- handleBadDebt dust/守恒、多市场守恒与坏账隔离（invariant + 多市场测试）

### 2.3 前端修复（全部已部署上线）
- Health Factor 空仓位显示 ∞；余额/份额 6s+后台刷新；交易成功即全量刷新
- Approve 一次授权 max；池写交易固定 gas 1,000,000（修连续交易 OOG）
- Repay：Max 精确 token 串（去科学计数/浮点）+ 金额钳制不超过债务 + 小额 8 位显示
- ETH 抵押提款修复（`withdrawCollateral(address,uint256)`）；pending 按钮统一“Waiting for wallet…”
- Borrow：档位实时“当前档位可借上限”+ 禁用原因红字；删除假的“收益率细分”
- Stress Test：准备金覆盖率跨 3 市场合计 + 演示假设明确标注
- 首页多市场卡片、Dashboard 市场/抵押选择器、Position 多抵押展示

### 2.4 测试网部署（Sepolia，已 5 次整组部署）
| 次 | 内容 | LendingPool 地址 |
|---|---|---|
| 1 | V2 多资产初版（含压缩） | `0x02f0d3…Eef6`（已归档） |
| 2 | + collectTreasury(uint8) | `0x8c38…8726`（已归档） |
| 3 | + 全额还款一次清零 | `0xc666…9481`（已归档） |
| 4 | + D1(旧序)+SafeERC20 | `0x7BAc…E8c`（已归档） |
| **5（当前）** | **D1 正确顺序**（物理→账面→存款人→Treasury 最后） | **`0xA958E9Ab95CEaFF5f341947824bA2237745Ec07D`** |
- 演示播种：USDC 5000 / USDT 3000 / DAI 15000 供应 + 0.01 ETH 抵押 + 可设价价格 + treasuryAddress
- 历次旧池资产仍在旧地址（仅存档，站点不再引用）

### 2.5 文档
- `ZZZ_Lend_完整文档.md`：架构/资产表/参数/部署地址(§6.7)/V2 附录(§9)/主网上线 GO-NO-GO(§9.7)
- `安全审计报告_V2多资产_2026-09-02.md`：11 节完整审计（D1/M1/L1-4/I1-5、28 向量、10 专项、8+5 补充、Gate10、优先级）
- `主网准备_本轮改动说明与遗留问题_2026-09-03.md`：本轮改动/做到位/遗留问题与不确定性
- `接手指南.md`：V2 快速上手

### 2.6 本轮新增：主网就绪部署模板（DeployMainnet.s.sol）
- **参数化模板**：真实 Chainlink feed（逐资产 feed 地址）、多签（MAINNET_ADMIN=Owner/角色持有、MAINNET_TREASURY、可独立 MAINNET_PAUSER）、**默认禁 settable**（不部署 SwitchableOracle，池价格源直连 ChainlinkOracle）、token 白名单（ENABLE_* 开关 + 逐资产 token/feed 配置项）
- 上链前**预检**：token/feed 非零、代码存在、feed decimals 匹配、answer>0、新鲜度 ≤2h；enabled 白名单资产缺配置即 revert
- 角色收口：池/oracle/RiskEngine 三角色授给多签后**撤销部署者**；IRM/RM/ReserveManager `transferOwnership(多签)`
- `.env.example` 已补主网变量注释；产物写 `deployments/mainnet.json`（区别于测试网 `sepolia.json`）

### 2.7 本轮新增：四组补强测试（PROGRESS §3.1 收尾）
| 文件 | 数 | 覆盖 |
|---|---|---|
| `DirectedFuzz.t.sol` | 7 | repay 部分/全额/跨市场边界 fuzz；liquidate closeFactor 封顶、seize 非零上限、跨市场(WBTC/USDT)、连续清算到清仓或坏账 |
| `ExtremeMatrix.t.sol` | 4 | closeFactor 5/50/100%、bonus 0/5/20%、reserveTarget 0/1%/50%、6×2×2 多档下跌组合的自动矩阵（全新池逐场景，守恒+溢出断言，产物落 test-out/） |
| `BadDebtFrontrunSnapshot.t.sol` | 4 | 坏账窗口 front-run 快照：抢先提款者逃损 vs 无人抢先按份分摊；快照恢复幂等；bank-run 受池现金上限约束 |
| `AdminBranches.t.sol` | 11 | addMarket zero/ETH/越权/超 MAX_MARKETS(8)；addCollateral zero/超 MAX_COLLATERALS(8)；非法 marketId/collateral 全操作 revert；角色矩阵；reserveTarget=100% 边界 |

---

## 3. 未完成待办
### 3.1 本环境可继续（已完成）
- ✅ Deploy 脚本“主网就绪”参数化模板（真实 feed / 多签 / 默认禁 settable / token 白名单配置项）→ `script/DeployMainnet.s.sol`
- ✅ 补强测试：repay/liquidate 定向 fuzz、closeFactor/bonus/reserve 极值矩阵、坏账 front-run 快照、addMarket/admin 分支覆盖 → 见 §2.7（29 suites / 215 passed）

### 3.2 外部 / 需决策（≈7 项，写入 §9.7）
1. 外部第三方安全审计 + 修复回归
2. 主网真实 Chainlink feed（ETH/USDC/USDT/DAI/WBTC/wstETH 或 wstETH 合成），移除 Mock/可设价
3. 主网 fork dress rehearsal（真实 token/feed/RPC）
4. 多签 + Timelock 治理；撤销部署者、隔离 Pauser/Treasury
5. 事件/索引（Subgraph）+ 清算与异常监控告警
6. 坏账 front-run（无延迟提款）公平策略（提款队列/锁窗，或正式公示承担模型）
7. 代币接入白名单 + 供应/抵押上限风控 + 真实历史 APY 数据源

---

## 4. 关键决策记录
| # | 决策 | 依据/备注 |
|---|---|---|
| K1 | V2 采用“单池多市场”方案（非每资产一池） | 复用 V1 记账闭环；已实现 3 市场×3 抵押 |
| K2 | tier 为全局仓位属性（跨市场同档，首借锁定） | 与 V1 语义一致，避免跨市场档位套利 |
| K3 | 按抵押资产分档 LTV/LT（WBTC 保守） | 需求指定 |
| K4 | 合约不可升级（无 proxy） | 已证明；任何修复=整组重部署+旧池归档。主网上线前需再评估是否引入升级方案 |
| K5 | 用户事件移除（为过 EIP-170） | 监控靠视图/轮询；主网需 Subgraph 补齐（未做） |
| K6 | 演示/测试网使用 SwitchableOracle 可设价 | USDC/USD feed stale + 其余无 Sepolia feed；**非主网方案** |
| K7 | 池写交易固定 gas 1,000,000；Approve 一次 max | 修复连续 OOG 与重复授权体验 |
| K8 | D1 坏账吸收顺序：物理→账面→存款人→**Treasury 最后** | 用户复核纠正（Treasury 是最后防线）；已上链 |
| K9 | 全额还款一次清零（repay ≥ 债务） | 消除尘埃尾巴；部分还款仍按取整 |
| K10 | SafeERC20 + “仅标准 ERC20”原则 | 兼容无返回值 token；禁 fee-on-transfer/rebasing |
| K11 | 94/4/2 分成、储备目标 ~3%、三段利率初值 | 需求给定，待真实流量验证 |
| K12 | “测试网功能版 ≠ 可上主网” | GO/NO-GO 见 §9.7；自审不替代外部审计 |

---

## 5. 风险与不确定（摘要）
详见 `docs/主网准备_本轮改动说明与遗留问题_2026-09-03.md`，要点：无外部审计；Oracle 中断锁“有债用户”降险；事件缺失靠轮询；坏账 front-run 无延迟；wstETH 真实兑换率/合成 feed 未验证；fuzz 覆盖面低；Sepolia 演示掩盖 feed 可用性；Smart Account（第三方钱包模块）兼容与报错提示待打磨；历次归档旧池资产需注意。

---

*本文档为进度总览，随项目推进更新；详细技术内容以主文档与专项文档为准。*
