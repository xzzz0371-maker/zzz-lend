# ZZZ Lend — Base 主网 fork dress rehearsal 报告

> 版本：v1.0 · 2026-09-03 ｜ fork：Base 主网（chainId 8453）@ `https://mainnet.base.org`（公共 RPC）
> 执行：`forge test --match-contract ForkMainnet -vvv --fork-url https://mainnet.base.org`
> 结果：**8 passed / 0 failed**（`contracts/test/ForkMainnet.t.sol`）

---

## 1. 背景与方案（含一次重要调整）

任务原假设在 Base 上可用 `wstETH/ETH` 合成 `wstETH/USD`，并在 fork 上用**真实代币**跑全流程。

实测发现两条现实约束，已按用户决策调整：

1. **Base 无官方 `wstETH/ETH` 或 `wstETH/USD` feed**（仅有 `wstETH/stETH` 汇率；`stETH/ETH` 检索到的是 Inception `instETH/ETH`，非 Lido stETH）。→ **Base V1 禁 wstETH 抵押**（`ENABLE_WSTETH=false`），V1 抵押 = ETH + cbBTC。
2. **Base 真实 USDC/USDT/DAI/cbBTC 在 foundry fork 上读正常、但 `approve` 写调用不可用**（无 data revert、非黑名单，typed 与 low-level 均复现）。→ 按用户决策采用 **「feed 真实 + 代币 Mock」**：价格源读取真实 Chainlink feed（只读验证通过），市场代币用本地 Mock（decimals 与 Base 真实一致：USDC/USDT=6、DAI=18、cbBTC=8）。

## 2. 部署（fork 上“主网参数版本”）

在 fork 上直接 new 部署全栈：`LendingPool(USDC-mock, ForkOracle, IRM(NORMAL), RiskManager, LiquidationManager, ReserveManager)`。

- 市场注册：USDT(market1,6dp)、DAI(market2,18dp)；USDC 为构造基座(market0)。
- 抵押品注册：cbBTC(8dp，保守档 45/55/65/70/75)；ETH 为构造内建（50/60/70/75/80）。
- 风控上限：各市场 supply cap 1,000,000 单位；cbBTC 未设 collateral cap（用 0=不限制便于用例）。
- 价格源 `ForkOracle`：默认 `latestRoundData()` 直读真实 Chainlink proxy；测试可 `setOverride` 单资产价模拟价格事件（覆盖清走不残留）。

## 3. 真实 feed / 真实代币读取（用例 pass）

| 项 | 结果 |
|---|---|
| 真实 USDC symbol/decimals | `USDC` / 6 ✅ |
| 真实 DAI symbol/decimals | `DAI` / 18 ✅ |
| 真实 cbBTC symbol/decimals | `cbBTC` / 8 ✅ |
| 真实 ETH/USD | ≈ $2505 ✅ |
| 真实 cbBTC/USD | ≈ $80801 ✅ |

## 4. 全流程用例结果

| 用例 | 覆盖 | 结果 |
|---|---|---|
| test_ForkRealTokensAndFeedsReadable | 真实 token/feed 读取 | ✅ |
| test_ForkSupplyThreeMarkets | A 10000 USDC / B 5000 USDT / C 8000 DAI 供应 + 三市场守恒 | ✅ |
| test_ForkCollateralizedBorrowing | D:10 ETH→借5000 USDC(T3)；E:0.2 cbBTC→借2000 USDT(T2)；tier 锁定 | ✅ |
| test_ForkRepayPartial | D 部分还款 2000 USDC，债务下降、守恒 | ✅ |
| test_ForkWithdraw | A 提现 3000 USDC，份额/余额/守恒正确 | ✅ |
| test_ForkLiquidationAfterPriceDrop | ETH 覆写 -45% → 可清算；清算后债务/抵押减少、清算人收 ETH | ✅ |
| test_ForkCbbtcLiquidationCrossAsset | cbBTC 覆写 -85% → 清算 cbBTC 抵押清 USDC 债（跨抵押×市场） | ✅ |
| test_ForkBadDebtHandled | 抵押清空仍留债 → handleBadDebt 吸收，债务清零、守恒 | ✅ |

## 5. 重点验证项结论

- **真实 Chainlink feed 价格读取**：OK（0 / 非 stale / desc 匹配，见健康脚本与上文）。
- **6/8/18 位精度跨资产**：供应/借款/还款/提现四市场均守恒（approx ≤1e6 raw）。
- **清算数学**：覆写价格暴跌后 `isLiquidatable` 正确；清算人 cover/seize、抵押扣减、HF 变化符合预期。
- **坏账**：抵押近 0 残债场景 `handleBadDebt` 吸收后债务清零、市场守恒。
- **tier**：首借锁定全局档位，跨市场借款同档（用例 D/E 各只借一个市场，未测同 tier 跨市场借——已由 Sepolia MultiAsset 覆盖）。
- **wstETH**：Base V1 不启用（见 §1）。

## 6. 发现的问题

1. **（环境，非合约）Base 真实代币 fork approve 不可用** → 已采用 feed 真实 + token Mock。真网部署前仍应以 `DeployMainnet.s.sol` 的预检 + feed 健康脚本复核；**建议正式上线前用付费 RPC（如 Alchemy/DRPC）对真实 token 做一次写路径 dress rehearsal**（approve+supply+borrow）。
2. **稳定币 feed 更新间隔可远超文档 heartbeat**（实测 11–13h）→ fork/主网预检若用固定 2h 会误报；已将 `DeployMainnet` 预检新鲜度放宽到 26h，逐资产心跳用 `scripts/feed-health-check`（heartbeat×N）。
3. fork 用公共 RPC 速度慢（用例共 ~30s CPU / 数十次 eth_call）；建议正式 rehearsal 用带 archive 的商业 RPC。

## 7. 结论

在「真实 feed + 本地同精度代币」的 fork 上，主网参数版本合约的供应/抵押/借款/还款/提现/清算/坏账/守恒全部通过。**代码层本轮 dress rehearsal 通过**；剩余真网前置 = 商业 RPC 下用真实 token 复跑 + 外部审计 + 权限收口（多签/Timelock，见对应手册）。
