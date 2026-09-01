import deployments from "./deployments/sepolia.json";

export const CHAIN_ID = 11155111;
export const ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

export const ADDRESSES = {
  lendingPool: deployments.lendingPool,
  usdc: deployments.usdc,
  switchableOracle: deployments.switchableOracle,
  chainlinkOracle: deployments.oracle,
  interestRateModel: deployments.interestRateModel,
  riskManager: deployments.riskManager,
  liquidationManager: deployments.liquidationManager,
  reserveManager: deployments.reserveManager,
  riskEngine: deployments.riskEngine,
};

export const RPC_URL =
  process.env.NEXT_PUBLIC_RPC_URL ?? "https://ethereum-sepolia-rpc.publicnode.com";

export const ETHERSCAN_URL = "https://sepolia.etherscan.io";

// WalletConnect project id (optional). Set NEXT_PUBLIC_WC_PROJECT_ID to enable WalletConnect.
export const WC_PROJECT_ID = process.env.NEXT_PUBLIC_WC_PROJECT_ID;

// Fallback ETH/USD price used when the on-chain oracle read fails (e.g. feed stale/paused).
// Demo fallback only; the app tries the live oracle first.
export const FALLBACK_ETH_PRICE = 2400;
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
