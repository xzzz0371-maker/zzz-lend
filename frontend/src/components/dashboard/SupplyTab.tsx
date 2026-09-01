"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi, MockUSDCAbi } from "@/lib/abis";
import { ADDRESSES, MIN_SUPPLY } from "@/lib/config";
import {
  usePoolStats,
  useUserPosition,
  useUsdcBalance,
  useUsdcAllowance,
  useBoostStatus,
  useBoostParams,
} from "@/lib/hooks";
import { formatUsdc, formatApy } from "@/lib/format";
import { TxStatus } from "./TxStatus";

const SECONDS_PER_DAY = 86400;

export function SupplyTab() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const { stats } = usePoolStats();
  const { position } = useUserPosition(address as Address);
  const balance = useUsdcBalance(address as Address);
  const { allowance, refetch: refetchAllowance } = useUsdcAllowance(
    address as Address,
    ADDRESSES.lendingPool as Address,
  );
  const { status: boostStatus, refetch: refetchBoost } = useBoostStatus(address as Address);
  const { boostRate, boostEndTime } = useBoostParams();

  const amountNum = parseFloat(amount);
  const raw = amountNum > 0 ? BigInt(Math.floor(amountNum * 1e6)) : 0n;
  const needApproval = raw > 0n && allowance < raw;

  const { data: hash, isPending, writeContract } = useWriteContract();

  const supplyAprPct = stats ? (Number(stats.supplyApr) / 1e18) * 100 : undefined;
  const valid = amountNum >= MIN_SUPPLY && raw > 0n && raw <= (balance ?? 0n);

  const utilAfter =
    stats && Number(stats.cash) + Number(raw) + Number(stats.totalBorrows) > 0
      ? (Number(stats.totalBorrows) /
          (Number(stats.cash) + Number(raw) + Number(stats.totalBorrows))) *
        100
      : 0;

  const boostEnabled = boostEndTime > 0n;
  const boostAprPct = Number(boostRate) / 1e18 * 100;
  const timeLeftDays = boostStatus ? Number(boostStatus.timeLeft) / SECONDS_PER_DAY : 0;

  return (
    <div className="space-y-4">
      <div className="rounded-lg bg-danger/10 px-3 py-2 text-xs text-danger">
        Deposits are not guaranteed. Your principal may decrease due to bad debt.
      </div>
      {boostEnabled && (
        <div className="rounded-xl bg-emerald-50 p-3 ring-1 ring-emerald-200">
          <div className="flex items-center justify-between">
            <div className="text-sm font-semibold text-emerald-700">Early Deposit Boost</div>
            <span className="pill bg-emerald-100 text-emerald-700">
              Tier 1/2 only · first 6 months
            </span>
          </div>
          <div className="mt-2 flex items-end justify-between">
            <div>
              <div className="text-xs text-slate-500">Boosted APY floor</div>
              <div className="font-display text-2xl font-bold text-emerald-600">
                ~{boostAprPct.toFixed(1)}%
              </div>
            </div>
            <div className="text-right text-xs text-slate-500">
              <div>{timeLeftDays >= 0 ? `${timeLeftDays.toFixed(0)} days left` : "Boost ended"}</div>
              <div>Cap: 10,000 USDC / wallet</div>
            </div>
          </div>
          {address && (
            <div className="mt-2 flex items-center justify-between border-t border-emerald-200/60 pt-2 text-xs">
              <div>
                <div className="text-slate-500">
                  Claimed:{" "}
                  <span className="font-semibold text-emerald-700">
                    {boostStatus ? formatUsdc(boostStatus.claimed) : "--"} USDC
                  </span>
                </div>
                <div className="text-slate-500">
                  Remaining allowance:{" "}
                  <span className="font-semibold text-emerald-700">
                    {boostStatus ? formatUsdc(boostStatus.remaining) : "--"} USDC
                  </span>
                </div>
              </div>
              <button
                className="btn-outline text-xs"
                disabled={!position || position.shares === 0n || isPending}
                onClick={() =>
                  writeContract({
                    address: ADDRESSES.lendingPool as Address,
                    abi: LendingPoolAbi,
                    functionName: "claimBoost",
                    args: [address as Address],
                  })
                }
              >
                {isPending ? "Claiming…" : "Claim Boost"}
              </button>
            </div>
          )}
          <p className="mt-2 text-[11px] text-emerald-700/70">
            Boost applies to interest only and does not protect principal. Deposits are not
            guaranteed.
          </p>
        </div>
      )}
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
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Projected Supply APY</span>
        <span className="text-success">{formatApy(supplyAprPct)}</span>
      </div>
      <div className="flex justify-between text-sm">
        <span className="text-slate-500">Pool utilization after</span>
        <span className="text-slate-800">{utilAfter.toFixed(2)}%</span>
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
