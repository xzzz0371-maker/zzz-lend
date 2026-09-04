import deploymentsRaw from "./deployments/base.json";
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const deployments = deploymentsRaw as any;

// Base mainnet (chainId 8453). Contract addresses are filled into
// deployments/base.json after real deployment; empty = not yet deployed.
export const CHAIN_ID = 8453;
export const ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
export const MAX_UINT =
  115792089237316195423570985008687907853269984665640564039457584007913129639935n;
// 池内函数含时间型利息累计与多市场健康检查，gas 波动大；给宽裕上限避免估算差导致 OOG（EIP-1559 只按实际用量收费）。
export const TX_GAS = 1_000_000n;

export const ADDRESSES = {
  lendingPool: deployments.lendingPool,
  usdc: deployments.usdc,
  usdt: deployments.usdt,
  dai: deployments.dai,
  cbbtc: deployments.cbbtc,
  wsteth: deployments.wsteth,
  wbtc: deployments.wbtc,
  switchableOracle: deployments.switchableOracle,
  chainlinkOracle: deployments.oracle,
  interestRateModel: deployments.interestRateModel,
  riskManager: deployments.riskManager,
  liquidationManager: deployments.liquidationManager,
  reserveManager: deployments.reserveManager,
  riskEngine: deployments.riskEngine,
};

export const RPC_URL =
  process.env.NEXT_PUBLIC_RPC_URL ?? "https://mainnet.base.org";

export const ETHERSCAN_URL = "https://basescan.org";

// WalletConnect project id (optional). Set NEXT_PUBLIC_WC_PROJECT_ID to enable WalletConnect.
export const WC_PROJECT_ID = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

// Fallback ETH/USD price used when the on-chain oracle read fails (e.g. feed stale/paused).
// Demo fallback only; the app tries the live oracle first. (Base ETH/USD feed ~$2506, 2026-09.)
export const FALLBACK_ETH_PRICE = 2506;
export const USDC_DECIMALS = 6;
export const ETH_DECIMALS = 18;
export const WAD = 1_000_000_000_000_000_000n;

// Minimum amounts enforced by the protocol (also enforced in the UI).
export const MIN_SUPPLY = 10;
export const MIN_BORROW = 100;
export const MIN_COLLATERAL = 0.01;

// Choose Your Risk tiers: max LTV % and liquidation threshold %.
export const TIERS = [
  { tier: 1, ltv: 50, lt: 60, label: "Tier 1 · LTV 50%", risk: "Low" },
  { tier: 2, ltv: 60, lt: 70, label: "Tier 2 · LTV 60%", risk: "Medium" },
  { tier: 3, ltv: 70, lt: 78, label: "Tier 3 · LTV 70%", risk: "High" },
  { tier: 4, ltv: 75, lt: 85, label: "Tier 4 · LTV 75%", risk: "Very High" },
  { tier: 5, ltv: 80, lt: 90, label: "Tier 5 · LTV 80%", risk: "Extreme" },
];

export const RISK_COLOR: Record<string, string> = {
  Low: "#22c55e",
  Medium: "#eab308",
  High: "#f97316",
  "Very High": "#ef4444",
  Extreme: "#b91c1c",
};

// ==================== V2 multi-asset ====================

export interface MarketInfo {
  id: number;
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  stable: boolean;
}

export interface CollateralInfo {
  id: number;
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  native: boolean; // native ETH
}

// Borrow markets (order = pool marketId; 0 = USDC default).
export const BORROW_MARKETS: MarketInfo[] = [
  { id: 0, symbol: "USDC", name: "USD Coin", address: deployments.usdc, decimals: 6, stable: true },
  { id: 1, symbol: "USDT", name: "Tether USD", address: deployments.usdt, decimals: 6, stable: true },
  { id: 2, symbol: "DAI", name: "Dai Stablecoin", address: deployments.dai, decimals: 18, stable: true },
];

// Collateral assets (order = pool collateral id; 0 = native ETH). Base V1: ETH + cbBTC
// (wstETH disabled on Base — no official wstETH/USD feed; WBTC replaced by cbBTC).
export const COLLATERALS: CollateralInfo[] = [
  { id: 0, symbol: "ETH", name: "Ether", address: ETH_ADDRESS, decimals: 18, native: true },
  { id: 1, symbol: "cbBTC", name: "Coinbase Wrapped BTC", address: deployments.cbbtc, decimals: 8, native: false },
];

export const ETH = ETH_ADDRESS;
export const SCALE = 1_000_000_000_000_000_000n; // 1e18 (WAD)

// Per-collateral LTV / liquidation thresholds (mirrors RiskManager V2).
// tiers 1..5 → maxLTV % and liquidation threshold %.
export const COLLATERAL_TIER_LTV: Record<string, number[]> = {
  ETH: [50, 60, 70, 75, 80],
  cbBTC: [45, 55, 65, 70, 75],
};
export const COLLATERAL_TIER_LT: Record<string, number[]> = {
  ETH: [60, 70, 78, 85, 90],
  cbBTC: [55, 65, 75, 80, 85],
};

export const MIN_COLLATERAL_TOKENS = 0.01; // whole tokens
