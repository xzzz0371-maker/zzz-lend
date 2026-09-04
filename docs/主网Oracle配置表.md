# ZZZ Lend — 主网 Oracle 配置表（Base · chainId 8453）

> 版本：v1.0 · 2026-09-03 ｜ 状态：**地址已链上实测核验**（Base 主网 RPC + Chainlink `description()/decimals()/latestRoundData()`），非凭记忆。
> 核对来源：Chainlink 官方文档地址页（docs.chain.link/data-feeds/price-feeds/addresses，Base 网络）SSR 数据 + 链上实证。部署前请再次以 data.chain.link 为准复核。

---

## 1. 结论摘要（重要）

- **Base 主网 V1 支持的抵押品：ETH（原生）、cbBTC（Coinbase Wrapped BTC）。**
- **wstETH 在 Base V1 禁用**：调研确认 Base 无官方 `wstETH/ETH` 或 `wstETH/USD` feed；官方仅有 `wstETH/stETH` 汇率（`0xB88BAc…`）。合成 wstETH/USD 需 `wstETH/stETH × stETH/ETH × ETH/USD`，而 **Base 无官方 `stETH/ETH`**（检索到同名地址实为 Inception `instETH/ETH`，非 Lido stETH）。→ 待 Chainlink 在 Base 上线 `wstETH/ETH`（或 `stETH/ETH`）官方 feed 后再启用。
- 合约保留 wstETH 抵押代码与 `ENABLE_WSTETH` 开关；`DeployMainnet.s.sol` 默认 `ENABLE_WSTETH=false`。
- 市场（借贷资产）：USDC（基座）、USDT、DAI，按 `ENABLE_*` 追加。

---

## 2. Base 官方 Chainlink 价格源（已链上实测）

| 用途 | 资产 | proxy 地址 | decimals | 实测价格(USD) | 实测新鲜度 | heartbeat* | 官方最低偏差* |
|---|---|---|---|---|---|---|---|
| 市场基座 | USDC/USD | `0x7e860098F58bBFC8648a4311b374B1D669a2bc6B` | 8 | 0.999978 | 22m ✅ | 86400s | 0.3% |
| 市场 | USDT/USD | `0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9` | 8 | 0.999780 | 49m ✅ | 86400s | 0.3% |
| 市场 | DAI/USD | `0x591e79239a7d679378eC8c847e5038150364C78F` | 8 | 1.000079 | 46m ✅ | 86400s | 0.3% |
| 抵押品 | ETH/USD | `0x50015f8b17fb2C290Dde41fDc246ed0dcEE93a8b` | 8 | 2492.56 | 69s ✅ | 86400s | 0.15% |
| 抵押品 | cbBTC/USD | `0x07DA0E54543a844a80ABE69c8A12F22B3aA59f9D` | 8 | 81071.26 | 18m ✅ | 86400s | 0.3% |

> \* heartbeat / 最低偏差为 Chainlink 文档地址页所列（Base 网络，Data Feed 类）。**稳定币为偏差型（deviation-driven）feed，实际更新时间可远超名义 heartbeat（实测 USDC/USDT/DAI 曾 11–13h 才更新）**；故 DeployMainnet 部署级预检新鲜度上限用 26h（拦“停更一天以上”），逐资产精细心跳监控由 `scripts/feed-health-check`（heartbeat×N）负责。

## 3. Base 官方代币合约（已链上实测 symbol/decimals）

| 资产 | 代币地址 | decimals | 说明 |
|---|---|---|---|
| USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | 6 | Circle 原生 USDC |
| USDT | `0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2` | 6 | 桥接 USDT |
| DAI | `0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb` | 18 | 桥接 DAI |
| cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | 8 | Coinbase Wrapped BTC |
| wstETH | `0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452` | 18 | **Base V1 不启用**（无官方 USD/ETH 合成源） |
| ETH | 原生 `0xEeee…EeeE` | 18 | 抵押品哨兵 |

> 注：Base 上曾存在 WBTC 代币桥接，但生态标准 BTC 为 cbBTC；且 WBTC/USD feed（`0xCCADC697…`）喂的是 Wrapped Bitcoin 价格，链上实测 $80489 可用，但 WBTC 代币在 Base 的流通/流动性存疑 → V1 采用 cbBTC 抵押。如需 WBTC 需另行核验其 Base 代币地址与流动性。

## 4. DeployMainnet.s.sol 内建默认（无需 env 即可部署正确地址）

| 字段 | 内建默认 |
|---|---|
| `MAINNET_ETH_USD_FEED` | `0x50015f8b…93a8b` |
| `MAINNET_USDC_TOKEN / _FEED` | `0x833589…2913` / `0x7e8600…2bc6B` |
| `MAINNET_USDT_TOKEN / _FEED` | `0xfde4C9…9bb2` / `0xf19d56…21F9` |
| `MAINNET_DAI_TOKEN / _FEED` | `0x50c572…0Cb` / `0x591e79…C78F` |
| `MAINNET_CBBTC_TOKEN / _FEED` | `0xcbB7C0…33Bf` / `0x07DA0E…9f9D` |
| `ENABLE_WSTETH` | `false`（Base V1 禁用） |

## 5. 上链预检（DeployMainnet `_preflight` 已实现）

- token/feed 非零、代码存在（ETH 哨兵除外）；
- feed `decimals()` == 配置值（USD 类 8）；
- `latestRoundData().answer > 0`；
- 新鲜度 `block.timestamp - updatedAt <= 2h`（心跳上限）；
- 任一 enabled 白名单资产缺配置 → 部署 revert。

## 6. 已知约束 / 待办

1. **wstETH 抵押**：Base 无官方源，V1 禁用；启用条件 = Chainlink 上线官方 `wstETH/ETH`（Lido）feed（或用 wstETH/stETH × stETH/ETH 且两源均官方）。
2. heartbeat/偏差值建议上线当日用 `scripts/feed-health-check` 再扫一遍（见 scripts/ 目录使用说明）。
3. 本表不替代 data.chain.link；上线前二次人工核对。
