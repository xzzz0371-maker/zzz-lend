"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { type Address } from "viem";
import { LendingPoolAbi, SwitchableOracleAbi } from "./abis";
import { ADDRESSES, ETH_ADDRESS, FALLBACK_ETH_PRICE } from "./config";
import { TIERS } from "./config";

const pool = { address: ADDRESSES.lendingPool as Address, abi: LendingPoolAbi } as const;

export interface PoolStats {
  totalSupply: bigint;
  totalBorrows: bigint;
  utilization: bigint;
  supplyApr: bigint;
  cash: bigint;
  totalReserve: bigint;
  treasuryAccrued: bigint;
  totalShares: bigint;
  supplyIndex: bigint;
}

export function usePoolStats() {
  const { data, isPending, isError } = useReadContracts({
    contracts: [
      { ...pool, functionName: "getTotalSupply" },
      { ...pool, functionName: "getTotalBorrows" },
      { ...pool, functionName: "getUtilization" },
      { ...pool, functionName: "getSupplyAPR" },
      { ...pool, functionName: "cash" },
      { ...pool, functionName: "totalReserve" },
      { ...pool, functionName: "treasuryAccrued" },
      { ...pool, functionName: "totalShares" },
      { ...pool, functionName: "supplyIndex" },
    ],
    query: { refetchInterval: 6_000, refetchIntervalInBackground: true },
  });

  const d = data as unknown as Array<{ result?: bigint }> | undefined;
  const stats: PoolStats | undefined = d
    ? {
        totalSupply: d[0]?.result ?? 0n,
        totalBorrows: d[1]?.result ?? 0n,
        utilization: d[2]?.result ?? 0n,
        supplyApr: d[3]?.result ?? 0n,
        cash: d[4]?.result ?? 0n,
        totalReserve: d[5]?.result ?? 0n,
        treasuryAccrued: d[6]?.result ?? 0n,
        totalShares: d[7]?.result ?? 0n,
        supplyIndex: d[8]?.result ?? 0n,
      }
    : undefined;

  return { stats, isPending, isError };
}

export function useBorrowAprs() {
  const { data } = useReadContracts({
    contracts: TIERS.map((t) => ({
      ...pool,
      functionName: "getBorrowAPR",
      args: [BigInt(t.tier)],
    })),
    query: { refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  const d = data as unknown as Array<{ result?: bigint }> | undefined;
  // getBorrowAPR returns WAD per year → convert to %.
  const aprs: Record<number, number> = {};
  if (d) {
    TIERS.forEach((t, i) => {
      aprs[t.tier] = (Number(d[i]?.result ?? 0n) / 1e18) * 100;
    });
  }
  return aprs;
}

export interface UserPosition {
  shares: bigint;
  collateral: bigint;
  debt: bigint; // WAD USD
  collateralValue: bigint; // WAD USD
  healthFactor: bigint;
  tier: bigint;
  liquidatable: boolean;
}

export function useUserPosition(user: Address | undefined) {
  const { data, refetch } = useReadContract({
    ...pool,
    functionName: "getUserPosition",
    args: user ? [user] : undefined,
    query: { enabled: !!user, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  const d = data as unknown as
    | [bigint, bigint, bigint, bigint, bigint, bigint, boolean]
    | undefined;
  const position: UserPosition | undefined = d
    ? {
        shares: d[0],
        collateral: d[1],
        debt: d[2],
        collateralValue: d[3],
        healthFactor: d[4],
        tier: d[5],
        liquidatable: d[6],
      }
    : undefined;
  return { position, refetch };
}

export function useMaxBorrowable(user: Address | undefined, tier: number) {
  const { data } = useReadContract({
    ...pool,
    functionName: "maxBorrowable",
    args: user && tier ? [user, BigInt(tier)] : undefined,
    query: { enabled: !!user && !!tier, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return (data as bigint | undefined) ?? 0n;
}

export interface Prices {
  ethUsd: number;
  usdcUsd: number;
  loading: boolean;
}


// Reads ETH/USD from the switchable oracle with a demo fallback if the feed is unavailable.
export function usePrices(): Prices {
  const { data: ethRaw } = useReadContract({
    address: ADDRESSES.switchableOracle as Address,
    abi: SwitchableOracleAbi,
    functionName: "getAssetPrice",
    args: [ETH_ADDRESS as Address],
    query: { refetchInterval: 30_000, refetchIntervalInBackground: true, retry: false },
  });
  const { data: usdcRaw } = useReadContract({
    address: ADDRESSES.switchableOracle as Address,
    abi: SwitchableOracleAbi,
    functionName: "getAssetPrice",
    args: [ADDRESSES.usdc as Address],
    query: { refetchInterval: 30_000, refetchIntervalInBackground: true, retry: false },
  });
  const ethUsd = ethRaw !== undefined && ethRaw !== null ? Number(ethRaw) / 1e8 : FALLBACK_ETH_PRICE;
  const usdcUsd = usdcRaw !== undefined && usdcRaw !== null ? Number(usdcRaw) / 1e8 : 1;
  return { ethUsd, usdcUsd, loading: false };
}

export function useUsdcBalance(user: Address | undefined) {
  const { data } = useReadContract({
    address: ADDRESSES.usdc as Address,
    abi: [
      {
        type: "function",
        name: "balanceOf",
        stateMutability: "view",
        inputs: [{ type: "address", name: "owner" }],
        outputs: [{ type: "uint256", name: "balance" }],
      },
    ],
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    query: { enabled: !!user, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return data as bigint | undefined;
}

export function useUsdcAllowance(owner: Address | undefined, spender: Address | undefined) {
  const { data, refetch } = useReadContract({
    address: ADDRESSES.usdc as Address,
    abi: [
      {
        type: "function",
        name: "allowance",
        stateMutability: "view",
        inputs: [{ type: "address", name: "owner" }, { type: "address", name: "spender" }],
        outputs: [{ type: "uint256", name: "" }],
      },
    ],
    functionName: "allowance",
    args: owner && spender ? [owner, spender] : undefined,
    query: { enabled: !!owner && !!spender, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return { allowance: (data as bigint | undefined) ?? 0n, refetch };
}

// ==================== V2 multi-asset hooks ====================

export interface MarketStats {
  supply: bigint;
  borrows: bigint;
  utilization: bigint;
  supplyApr: bigint;
  cash: bigint;
  reserve: bigint;
  treasury: bigint;
  supplyIndex: bigint;
}

export function useMarketStats(marketId: number) {
  const { data, isPending, isError } = useReadContracts({
    contracts: [
      { ...pool, functionName: "marketAccounts", args: [BigInt(marketId)] },
      { ...pool, functionName: "marketUtilization", args: [BigInt(marketId)] },
      { ...pool, functionName: "marketSupplyAPR", args: [BigInt(marketId)] },
    ],
    query: { refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  const d = data as unknown as Array<{ result?: unknown }> | undefined;
  const acc = d?.[0]?.result as [bigint, bigint, bigint, bigint, bigint, bigint] | undefined;
  const stats: MarketStats | undefined = acc
    ? {
        cash: acc[0],
        borrows: acc[1],
        supply: acc[2],
        reserve: acc[3],
        treasury: acc[4],
        supplyIndex: acc[5],
        utilization: (d?.[1]?.result as bigint) ?? 0n,
        supplyApr: (d?.[2]?.result as bigint) ?? 0n,
      }
    : undefined;
  return { stats, isPending, isError };
}

export function useMarketBorrowAprs(marketId: number) {
  const { data } = useReadContracts({
    contracts: TIERS.map((t) => ({
      ...pool,
      functionName: "marketBorrowAPR",
      args: [BigInt(marketId), BigInt(t.tier)],
    })),
    query: { refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  const d = data as unknown as Array<{ result?: bigint }> | undefined;
  const aprs: Record<number, number> = {};
  if (d) {
    TIERS.forEach((t, i) => {
      aprs[t.tier] = (Number(d[i]?.result ?? 0n) / 1e18) * 100;
    });
  }
  return aprs;
}

export function useUserSharesOf(user: Address | undefined, marketId: number) {
  const { data } = useReadContract({
    ...pool,
    functionName: "userSharesOf",
    args: user ? [user, BigInt(marketId)] : undefined,
    query: { enabled: !!user, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return (data as bigint | undefined) ?? 0n;
}

// Reads USD price (8-decimals → float) for a list of asset addresses.
export function useAssetPrices(addresses: string[]): Record<string, number> {
  const { data } = useReadContracts({
    contracts: addresses.map((a) => ({
      address: ADDRESSES.switchableOracle as Address,
      abi: SwitchableOracleAbi,
      functionName: "getAssetPrice",
      args: [a as Address],
    })),
    query: { refetchInterval: 30_000, refetchIntervalInBackground: true, retry: false },
  });
  const d = data as unknown as Array<{ result?: bigint }> | undefined;
  const out: Record<string, number> = {};
  if (d) {
    addresses.forEach((a, i) => {
      const raw = d[i]?.result;
      out[a] = raw !== undefined && raw !== null ? Number(raw) / 1e8 : 0;
    });
  }
  return out;
}

export interface PositionV2 {
  debtWad: bigint;
  collateralValueWad: bigint;
  healthFactor: bigint;
  liquidatable: boolean;
  tier: bigint;
  collateral: Record<number, bigint>;
  marketDebt: Record<number, bigint>;
}

export function useUserPositionV2(user: Address | undefined) {
  const addresses = user ? [user] : undefined;
  const { data, refetch } = useReadContracts({
    contracts: [
      { ...pool, functionName: "getUserPositionV2", args: addresses },
      { ...pool, functionName: "userGlobalTier", args: addresses },
      { ...pool, functionName: "userCollateralOf", args: user ? [user, 0n] : undefined },
      { ...pool, functionName: "userCollateralOf", args: user ? [user, 1n] : undefined },
      { ...pool, functionName: "userCollateralOf", args: user ? [user, 2n] : undefined },
      { ...pool, functionName: "userDebtToken", args: user ? [user, 0n] : undefined },
      { ...pool, functionName: "userDebtToken", args: user ? [user, 1n] : undefined },
      { ...pool, functionName: "userDebtToken", args: user ? [user, 2n] : undefined },
    ],
    query: { enabled: !!user, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  const d = data as unknown as Array<{ result?: unknown }> | undefined;
  const g = d?.[0]?.result as [bigint, bigint, bigint, boolean] | undefined;
  const pos: PositionV2 | undefined = user && d
    ? {
        debtWad: g?.[0] ?? 0n,
        collateralValueWad: g?.[1] ?? 0n,
        healthFactor: g?.[2] ?? 0n,
        liquidatable: g?.[3] ?? false,
        tier: (d[1]?.result as bigint) ?? 0n,
        collateral: {
          0: (d[2]?.result as bigint) ?? 0n,
          1: (d[3]?.result as bigint) ?? 0n,
          2: (d[4]?.result as bigint) ?? 0n,
        },
        marketDebt: {
          0: (d[5]?.result as bigint) ?? 0n,
          1: (d[6]?.result as bigint) ?? 0n,
          2: (d[7]?.result as bigint) ?? 0n,
        },
      }
    : undefined;
  return { position: pos, refetch };
}

// Generic ERC20 balance / allowance (also used for ETH native below).
const erc20ViewAbi = [
  {
    type: "function",
    name: "balanceOf",
    stateMutability: "view",
    inputs: [{ type: "address", name: "owner" }],
    outputs: [{ type: "uint256", name: "balance" }],
  },
  {
    type: "function",
    name: "allowance",
    stateMutability: "view",
    inputs: [{ type: "address", name: "owner" }, { type: "address", name: "spender" }],
    outputs: [{ type: "uint256", name: "" }],
  },
] as const;

export function useTokenBalance(token: Address | undefined, user: Address | undefined) {
  const { data } = useReadContract({
    address: token,
    abi: erc20ViewAbi,
    functionName: "balanceOf",
    args: user ? [user] : undefined,
    query: { enabled: !!user && !!token, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return (data as bigint | undefined) ?? 0n;
}

export function useTokenAllowance(token: Address | undefined, user: Address | undefined, spender: Address | undefined) {
  const { data, refetch } = useReadContract({
    address: token,
    abi: erc20ViewAbi,
    functionName: "allowance",
    args: user && spender ? [user, spender] : undefined,
    query: { enabled: !!user && !!spender && !!token, refetchInterval: 6_000, refetchIntervalInBackground: true },
  });
  return { allowance: (data as bigint | undefined) ?? 0n, refetch };
}
