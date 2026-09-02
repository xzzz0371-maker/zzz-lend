"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi } from "@/lib/abis";
import { ADDRESSES, type MarketInfo } from "@/lib/config";
import { useMarketStats, useUserSharesOf } from "@/lib/hooks";
import { formatToken, numToRaw, rawToNum } from "@/lib/format";
import { TxStatus } from "./TxStatus";

export function WithdrawTab({ market }: { market: MarketInfo }) {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { stats } = useMarketStats(market.id);
  const shares = useUserSharesOf(address as Address, market.id);

  const { data: hash, isPending, writeContract } = useWriteContract();

  const amountNum = parseFloat(amount);
  const raw = numToRaw(amountNum, market.decimals);
  // shares = rawToken * WAD / supplyIndex
  const sharesNeeded =
    raw > 0n && stats && stats.supplyIndex > 0n ? (raw * BigInt(1e18)) / stats.supplyIndex : 0n;

  const withdrawable =
    stats && stats.supplyIndex > 0n ? (shares * stats.supplyIndex) / BigInt(1e18) : 0n;
  const valid =
    !!stats && raw > 0n && sharesNeeded > 0n && sharesNeeded <= shares && withdrawable >= raw;
  const liquidityOk = !!stats && raw <= stats.cash;

  const remaining = raw > 0n ? (withdrawable > raw ? withdrawable - raw : 0n) : withdrawable;

  return (
    <div className="space-y-4">
      <div>
        <label className="label">Amount ({market.symbol})</label>
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
            onClick={() => setAmount(rawToNum(withdrawable, market.decimals).toString())}
          >
            Max
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          Withdrawable: {formatToken(withdrawable, market.decimals)} {market.symbol}
        </p>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Remaining deposit after</span>
        <span className="text-slate-800">
          {formatToken(remaining, market.decimals)} {market.symbol}
        </span>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Available liquidity</span>
        <span className={liquidityOk ? "text-success" : "text-danger"}>
          {formatToken(stats?.cash, market.decimals)} {market.symbol}
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
            args: [BigInt(market.id), sharesNeeded],
          })
        }
      >
        {isPending ? "Withdrawing…" : "Withdraw"}
      </button>
      <TxStatus hash={hash} />
      <div className="border-t border-slate-200/70 pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Your supply shares</span>
          <span className="text-slate-800">{formatToken(shares, market.decimals)}</span>
        </div>
      </div>
    </div>
  );
}
