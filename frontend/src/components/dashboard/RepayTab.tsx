"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi, MockTokenAbi } from "@/lib/abis";
import { ADDRESSES, type MarketInfo } from "@/lib/config";
import { useUserPositionV2, useTokenAllowance } from "@/lib/hooks";
import { formatToken, numToRaw, rawToNum, formatHealthFactor } from "@/lib/format";
import { TxStatus } from "./TxStatus";

export function RepayTab({ market }: { market: MarketInfo }) {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { position } = useUserPositionV2(address as Address);
  const { allowance, refetch: refetchAllowance } = useTokenAllowance(
    market.address as Address,
    address as Address,
    ADDRESSES.lendingPool as Address,
  );

  const { data: hash, isPending, writeContract } = useWriteContract();

  const debtRaw = position ? position.marketDebt[market.id] ?? 0n : 0n;
  const amountNum = parseFloat(amount);
  const raw = numToRaw(amountNum, market.decimals);
  const needApproval = raw > 0n && allowance < raw;
  const valid = raw > 0n && raw <= debtRaw;
  const remaining = debtRaw > raw ? debtRaw - raw : 0n;

  return (
    <div className="space-y-4">
      <div>
        <label className="label">Repay amount ({market.symbol})</label>
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
            onClick={() => setAmount(rawToNum(debtRaw, market.decimals).toString())}
          >
            Max
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">
          Current debt: {formatToken(debtRaw, market.decimals)} {market.symbol}
        </p>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Remaining debt after</span>
        <span className="text-slate-800">
          {formatToken(remaining, market.decimals)} {market.symbol}
        </span>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Health Factor</span>
        <span className="text-slate-800">
          {position && position.healthFactor > 0n ? formatHealthFactor(position.healthFactor) : "--"}
        </span>
      </div>
      {needApproval ? (
        <button
          className="btn-primary w-full"
          disabled={!address || !valid || isPending}
          onClick={() =>
            writeContract({
              address: market.address as Address,
              abi: MockTokenAbi,
              functionName: "approve",
              args: [ADDRESSES.lendingPool as Address, raw],
            })
          }
        >
          {isPending ? "Approving…" : `Approve ${market.symbol}`}
        </button>
      ) : (
        <button
          className="btn-primary w-full"
          disabled={!address || !valid || isPending}
          onClick={() =>
            writeContract({
              address: ADDRESSES.lendingPool as Address,
              abi: LendingPoolAbi,
              functionName: "repay",
              args: [BigInt(market.id), raw],
            })
          }
        >
          {isPending ? "Repaying…" : "Repay"}
        </button>
      )}
      <TxStatus hash={hash} />
      <div className="border-t border-slate-200/70 pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Accrued interest included</span>
          <span className="text-slate-800">Yes (in debt)</span>
        </div>
        <button
          className="mt-1 text-xs text-accent hover:underline"
          onClick={() => refetchAllowance()}
        >
          Refresh allowance
        </button>
      </div>
    </div>
  );
}
