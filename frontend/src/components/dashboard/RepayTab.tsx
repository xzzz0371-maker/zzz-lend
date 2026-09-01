"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi, MockUSDCAbi } from "@/lib/abis";
import { ADDRESSES } from "@/lib/config";
import { useUserPosition, useUsdcAllowance } from "@/lib/hooks";
import { formatUsdc, formatHealthFactor, hfTone } from "@/lib/format";
import { TxStatus } from "./TxStatus";

export function RepayTab() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { position } = useUserPosition(address as Address);
  const { allowance, refetch: refetchAllowance } = useUsdcAllowance(
    address as Address,
    ADDRESSES.lendingPool as Address,
  );

  const { data: hash, isPending, writeContract } = useWriteContract();

  const debtRaw = position ? position.debt / BigInt(1e12) : 0n; // USDC6
  const amountNum = parseFloat(amount);
  const raw = amountNum > 0 ? BigInt(Math.floor(amountNum * 1e6)) : 0n;
  const needApproval = raw > 0n && allowance < raw;
  const valid = raw > 0n && raw <= debtRaw;

  const remaining = debtRaw > raw ? debtRaw - raw : 0n;
  // Approximate HF improvement: same formula as contract.
  const remainingWad = remaining * BigInt(1e12);
  const projHf =
    position && position.collateralValue > 0n && remainingWad > 0n
      ? (Number(position.collateralValue) * 0.78) / (Number(remainingWad) / 1e18)
      : 0;
  const projHfBig = projHf > 0 ? BigInt(Math.floor(projHf * 1e18)) : 0n;

  return (
    <div className="space-y-4">
      <div>
        <label className="label">Repay amount (USDC)</label>
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
            onClick={() => setAmount((Number(debtRaw) / 1e6).toString())}
          >
            Max
          </button>
        </div>
        <p className="mt-1 text-xs text-slate-500">Current debt: {formatUsdc(debtRaw)} USDC</p>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-400">Remaining debt after</span>
        <span className="text-slate-100">{formatUsdc(remaining)} USDC</span>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-400">Health Factor after</span>
        <span className={hfTone(projHfBig) === "danger" ? "text-danger" : "text-slate-100"}>
          {formatHealthFactor(projHfBig)}
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
              functionName: "repay",
              args: [raw],
            })
          }
        >
          {isPending ? "Repaying…" : "Repay"}
        </button>
      )}
      <TxStatus hash={hash} />
      <div className="border-t border-border pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-400">Current debt</span>
          <span className="text-slate-100">{formatUsdc(debtRaw)} USDC</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-400">Accrued interest included</span>
          <span className="text-slate-100">Yes (in debt)</span>
        </div>
      </div>
    </div>
  );
}
