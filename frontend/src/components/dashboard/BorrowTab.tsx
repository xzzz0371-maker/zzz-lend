"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi } from "@/lib/abis";
import { ADDRESSES, MIN_BORROW, TIERS } from "@/lib/config";
import { useUserPosition, useMaxBorrowable, useBorrowAprs, usePoolStats } from "@/lib/hooks";
import { formatUsdc, formatApy, formatHealthFactor, hfTone } from "@/lib/format";
import { borrowAprAt } from "@/lib/rates";
import { YieldBreakdown } from "@/components/YieldBreakdown";
import { TxStatus } from "./TxStatus";

export function BorrowTab({ initialTier }: { initialTier: number }) {
  const { address } = useAccount();
  const [tier, setTier] = useState(initialTier);
  const [amount, setAmount] = useState("");
  const [showBreakdown, setShowBreakdown] = useState(false);
  const { position } = useUserPosition(address as Address);
  const maxBorrow = useMaxBorrowable(address as Address, tier);
  const borrowAprs = useBorrowAprs();
  const { stats } = usePoolStats();

  const { data: hash, isPending, writeContract } = useWriteContract();

  const cfg = TIERS.find((t) => t.tier === tier)!;
  const amountNum = parseFloat(amount);
  const raw = amountNum > 0 ? BigInt(Math.floor(amountNum * 1e6)) : 0n;
  const amountWad = raw * BigInt(1e12);

  const debt = position?.debt ?? 0n;
  const collateralValue = position?.collateralValue ?? 0n;
  const newDebt = debt + amountWad;
  const projLtv = collateralValue > 0n ? (Number(newDebt) / Number(collateralValue)) * 100 : 0;
  const projHf =
    collateralValue > 0n && newDebt > 0n
      ? (Number(collateralValue) * (cfg.lt / 100)) / (Number(newDebt) / 1e18)
      : 0;
  const projHfBig = projHf > 0 ? BigInt(Math.floor(projHf * 1e18)) : 0n;

  const tierLocked = position && position.tier > 0n && Number(position.tier) !== tier;
  const valid =
    amountNum >= MIN_BORROW && raw > 0n && raw <= maxBorrow && !tierLocked && collateralValue > 0n;

  const borrowApr = borrowAprs[tier];
  const utilPct = stats ? (Number(stats.utilization) / 1e18) * 100 : 0;
  // Estimated rate band across ±10pt utilization, plus a demo 7D range.
  const rangeLow = borrowAprAt(Math.max(0, utilPct - 10), tier);
  const rangeHigh = borrowAprAt(Math.min(100, utilPct + 10), tier);
  const range7dLow = Math.max(0, rangeLow - 0.3);
  const range7dHigh = rangeHigh + 0.3;
  const grossYield = borrowApr !== undefined ? borrowApr * utilFactor() : undefined;

  function utilFactor() {
    return utilPct > 0 ? utilPct / 100 : 0.5; // demo utilization factor
  }

  return (
    <div className="space-y-4">
      <div className="rounded-lg bg-warning/10 px-3 py-2 text-xs text-warning">
        Borrowing involves liquidation risk. If Health Factor drops below 1, your collateral may be
        liquidated.
      </div>

      {/* Tier selector */}
      <div>
        <label className="label">Choose your risk tier</label>
        <div className="grid grid-cols-5 gap-1">
          {TIERS.map((t) => (
            <button
              key={t.tier}
              onClick={() => setTier(t.tier)}
              className={`rounded-lg border px-1 py-2 text-center text-xs ${
                tier === t.tier
                  ? "border-accent bg-accent/10 text-white"
                  : "border-slate-200/70 text-slate-500 hover:border-accent"
              }`}
            >
              {t.ltv}%
            </button>
          ))}
        </div>
        <p className="mt-1 text-xs text-slate-500">
          {cfg.label} · Liquidation threshold {cfg.lt}% · Estimated, not guaranteed
        </p>
      </div>

      {tierLocked && (
        <p className="text-xs text-danger">
          You already borrowed at tier {Number(position?.tier)}. Repay in full to switch tiers.
        </p>
      )}

      <div>
        <label className="label">Borrow amount (USDC)</label>
        <input
          type="number"
          className="input"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        <p className="mt-1 text-xs text-slate-500">
          Min {MIN_BORROW} USDC · Max borrowable: {formatUsdc(maxBorrow)} USDC
        </p>
      </div>

      <div className="rounded-lg bg-sky-50 px-3 py-2 text-xs text-sky-700 ring-1 ring-sky-200">
        Interest rates are variable and change with pool utilization. Your actual interest cost may
        differ from the rate shown at borrow time.
      </div>

      <div className="space-y-1 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Borrow APR · Tier {tier}</span>
          <span className="font-semibold text-slate-800">
            {rangeLow.toFixed(2)}% – {rangeHigh.toFixed(2)}% / Current: {formatApy(borrowApr)}
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">7D Range (estimated)</span>
          <span className="text-slate-800">
            {range7dLow.toFixed(2)}% – {range7dHigh.toFixed(2)}%
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Utilization</span>
          <span className="text-slate-800">{utilPct.toFixed(2)}%</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Max LTV</span>
          <span className="text-slate-800">{cfg.ltv}%</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">LTV after borrow</span>
          <span className={projLtv > cfg.ltv ? "text-danger" : "text-slate-800"}>
            {projLtv.toFixed(2)}%
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Health Factor after</span>
          <span className={hfTone(projHfBig) === "danger" ? "text-danger" : "text-slate-800"}>
            {formatHealthFactor(projHfBig)}
          </span>
        </div>
      </div>

      {/* Yield breakdown */}
      <div>
        <button
          className="text-sm font-medium text-accent hover:underline"
          onClick={() => setShowBreakdown((v) => !v)}
        >
          {showBreakdown ? "▾" : "▸"} Yield breakdown (estimated)
        </button>
        {showBreakdown && grossYield !== undefined && (
          <div className="mt-2 rounded-xl bg-white/60 p-3 ring-1 ring-slate-200/60">
            <YieldBreakdown gross={grossYield} />
          </div>
        )}
      </div>

      <button
        className="btn-primary w-full"
        disabled={!address || !valid || isPending}
        onClick={() =>
          writeContract({
            address: ADDRESSES.lendingPool as Address,
            abi: LendingPoolAbi,
            functionName: "borrow",
            args: [raw, BigInt(tier)],
          })
        }
      >
        {isPending ? "Borrowing…" : "Borrow"}
      </button>
      <TxStatus hash={hash} />

      <div className="border-t border-slate-200/70 pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Current debt</span>
          <span className="text-slate-800">{formatUsdc(debt / BigInt(1e12))}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Current tier</span>
          <span className="text-slate-800">
            {position && position.tier > 0n ? `Tier ${Number(position.tier)}` : "None"}
          </span>
        </div>
      </div>
    </div>
  );
}
