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
    query: { refetchInterval: 12_000 },
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
    query: { refetchInterval: 12_000 },
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
    query: { enabled: !!user, refetchInterval: 12_000 },
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
    query: { enabled: !!user && !!tier, refetchInterval: 12_000 },
  });
  return (data as bigint | undefined) ?? 0n;
}

export interface Prices {
  ethUsd: number;
  usdcUsd: number;
  loading: boolean;
}

export interface BoostStatus {
  eligible: bigint;
  claimed: bigint;
  remaining: bigint;
  boostPoolBalance: bigint;
  timeLeft: bigint; // seconds
}

export function useBoostStatus(user: Address | undefined) {
  const { data, refetch } = useReadContract({
    ...pool,
    functionName: "getBoostStatus",
    args: user ? [user] : undefined,
    query: { enabled: !!user, refetchInterval: 12_000 },
  });
  const d = data as unknown as [bigint, bigint, bigint, bigint, bigint] | undefined;
  const status: BoostStatus | undefined = d
    ? { eligible: d[0], claimed: d[1], remaining: d[2], boostPoolBalance: d[3], timeLeft: d[4] }
    : undefined;
  return { status, refetch };
}

export function useBoostParams() {
  const { data: rate } = useReadContract({
    ...pool,
    functionName: "boostRate",
    query: { refetchInterval: 60_000 },
  });
  const { data: endTime } = useReadContract({
    ...pool,
    functionName: "boostEndTime",
    query: { refetchInterval: 60_000 },
  });
  const { data: startTime } = useReadContract({
    ...pool,
    functionName: "boostStartTime",
    query: { refetchInterval: 60_000 },
  });
  return {
    boostRate: (rate as bigint | undefined) ?? 0n,
    boostEndTime: (endTime as bigint | undefined) ?? 0n,
    boostStartTime: (startTime as bigint | undefined) ?? 0n,
  };
}


// Reads ETH/USD from the switchable oracle with a demo fallback if the feed is unavailable.
export function usePrices(): Prices {
  const { data: ethRaw } = useReadContract({
    address: ADDRESSES.switchableOracle as Address,
    abi: SwitchableOracleAbi,
    functionName: "getAssetPrice",
    args: [ETH_ADDRESS as Address],
    query: { refetchInterval: 30_000, retry: false },
  });
  const { data: usdcRaw } = useReadContract({
    address: ADDRESSES.switchableOracle as Address,
    abi: SwitchableOracleAbi,
    functionName: "getAssetPrice",
    args: [ADDRESSES.usdc as Address],
    query: { refetchInterval: 30_000, retry: false },
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
    query: { enabled: !!user, refetchInterval: 12_000 },
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
    query: { enabled: !!owner && !!spender, refetchInterval: 12_000 },
  });
  return { allowance: (data as bigint | undefined) ?? 0n, refetch };
}
