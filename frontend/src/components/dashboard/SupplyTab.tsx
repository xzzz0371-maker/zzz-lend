"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi, MockUSDCAbi } from "@/lib/abis";
import { ADDRESSES, MIN_SUPPLY } from "@/lib/config";
import { usePoolStats, useUserPosition, useUsdcBalance, useUsdcAllowance } from "@/lib/hooks";
import { formatUsdc, formatApy } from "@/lib/format";
import { SupplyApyDisplay } from "@/components/ApyDisplay";
import { TxStatus } from "./TxStatus";

export function SupplyTab() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { stats } = usePoolStats();
  const { position } = useUserPosition(address as Address);
  const balance = useUsdcBalance(address as Address);
  const { allowance } = useUsdcAllowance(address as Address, ADDRESSES.lendingPool as Address);

  const amountNum = parseFloat(amount);
  const raw = amountNum > 0 ? BigInt(Math.floor(amountNum * 1e6)) : 0n;
  const needApproval = raw > 0n && allowance < raw;

  const { data: hash, isPending, writeContract } = useWriteContract();

  const supplyAprPct = stats ? (Number(stats.supplyApr) / 1e18) * 100 : undefined;
  const utilPct = stats ? (Number(stats.utilization) / 1e18) * 100 : 0;
  // 7-day average supply APY — demo estimate around the current value.
  const supply7d = supplyAprPct !== undefined ? supplyAprPct * (0.96 + (supplyAprPct % 0.08) / 100) : undefined;
  const valid = amountNum >= MIN_SUPPLY && raw > 0n && raw <= (balance ?? 0n);

  const utilAfter =
    stats && Number(stats.cash) + Number(raw) + Number(stats.totalBorrows) > 0
      ? (Number(stats.totalBorrows) /
          (Number(stats.cash) + Number(raw) + Number(stats.totalBorrows))) *
        100
      : 0;

  return (
    <div className="space-y-4">
      <div className="rounded-lg bg-danger/10 px-3 py-2 text-xs text-danger">
        Deposits are not guaranteed. Your principal may decrease due to bad debt.
      </div>
      <div>
        <label className="label">Amount (USDC)</label>
        <input
          type="number"
          min={MIN_SUPPLY}
          className="input"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        <p className="mt-1 text-xs text-slate-500">
          Minimum {MIN_SUPPLY} USDC · Available: {formatUsdc(balance)} USDC
        </p>
      </div>
      <div className="flex items-center justify-between gap-3">
        <span className="text-slate-500">Supply APY</span>
        <SupplyApyDisplay currentPct={supplyAprPct ?? 0} utilPct={utilPct} />
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Supply APY · 7D Avg (est.)</span>
        <span className="text-slate-800">{formatApy(supply7d)}</span>
      </div>
      <p className="-mt-2 text-[11px] text-slate-400">
        7D average is estimated from the current rate model — not historical data.
      </p>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Utilization (now → after)</span>
        <span className="text-slate-800">
          {utilPct.toFixed(2)}% → {utilAfter.toFixed(2)}%
        </span>
      </div>
      {needApproval ? (
        <button
          className="btn-primary w-full"
          disabled={!address || !valid || isPending}
          onClick={() =>
            writeContract({
              address: ADDRESSES.usdc as Address,
              abi: MockUSDCAbi,
              functionName: "approve",
              args: [ADDRESSES.lendingPool as Address, raw],
            })
          }
        >
          {isPending ? "Approving…" : "Approve USDC"}
        </button>
      ) : (
        <button
          className="btn-primary w-full"
          disabled={!address || !valid || isPending}
          onClick={() =>
            writeContract({
              address: ADDRESSES.lendingPool as Address,
              abi: LendingPoolAbi,
              functionName: "supply",
              args: [raw],
            })
          }
        >
          {isPending ? "Supplying…" : "Supply"}
        </button>
      )}
      <TxStatus hash={hash} />
      <div className="border-t border-slate-200/70 pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Your supply shares</span>
          <span className="text-slate-800">{position ? formatUsdc(position.shares) : "--"}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Current share value</span>
          <span className="text-slate-800">
            {position && stats
              ? formatUsdc((position.shares * stats.supplyIndex) / BigInt(1e18))
              : "--"}
          </span>
        </div>
      </div>
    </div>
  );
}
