"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi } from "@/lib/abis";
import { ADDRESSES } from "@/lib/config";
import { usePoolStats, useUserPosition } from "@/lib/hooks";
import { formatUsdc } from "@/lib/format";
import { TxStatus } from "./TxStatus";

export function WithdrawTab() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { stats } = usePoolStats();
  const { position } = useUserPosition(address as Address);

  const { data: hash, isPending, writeContract } = useWriteContract();

  const amountNum = parseFloat(amount);
  const rawUsdc = amountNum > 0 ? BigInt(Math.floor(amountNum * 1e6)) : 0n;
  // shares = usdc6 * WAD / supplyIndex
  const shares =
    rawUsdc > 0n && stats && stats.supplyIndex > 0n
      ? (rawUsdc * BigInt(1e18)) / stats.supplyIndex
      : 0n;

  const withdrawable = position && stats ? (position.shares * stats.supplyIndex) / BigInt(1e18) : 0n;
  const valid =
    !!position && rawUsdc > 0n && shares > 0n && shares <= position.shares && withdrawable >= rawUsdc;
  const liquidityOk = !!stats && rawUsdc <= stats.cash;

  const remaining = position && rawUsdc > 0n ? (withdrawable > rawUsdc ? withdrawable - rawUsdc : 0n) : withdrawable;

  return (
    <div className="space-y-4">
      <div>
        <label className="label">Amount (USDC)</label>
        <div className="flex gap-2">
          <input
            type="number"
            className="input"
            placeholder="0.00"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
          />
          <button
            className="btn-outline whitespace-nowrap"
            onClick={() => setAmount((Number(withdrawable) / 1e6).toString())}
          >
            Max
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          Withdrawable: {formatUsdc(withdrawable)} USDC
        </p>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Remaining deposit after</span>
        <span className="text-slate-800">{formatUsdc(remaining)} USDC</span>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Available liquidity</span>
        <span className={liquidityOk ? "text-success" : "text-danger"}>
          {formatUsdc(stats?.cash)} USDC
        </span>
      </div>
      {!liquidityOk && valid && (
        <p className="text-xs text-danger">
          Pool liquidity is insufficient — withdrawals may fail.
        </p>
      )}
      <button
        className="btn-primary w-full"
        disabled={!address || !valid || !liquidityOk || isPending}
        onClick={() =>
          writeContract({
            address: ADDRESSES.lendingPool as Address,
            abi: LendingPoolAbi,
            functionName: "withdraw",
            args: [shares],
          })
        }
      >
        {isPending ? "Withdrawing…" : "Withdraw"}
      </button>
      <TxStatus hash={hash} />
      <div className="border-t border-slate-200/70 pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Your supply shares</span>
          <span className="text-slate-800">{position ? formatUsdc(position.shares) : "--"}</span>
        </div>
      </div>
    </div>
  );
}
