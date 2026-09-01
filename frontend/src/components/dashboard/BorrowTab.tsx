"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi } from "@/lib/abis";
import { ADDRESSES, MIN_BORROW, TIERS } from "@/lib/config";
import { useUserPosition, useMaxBorrowable, useBorrowAprs } from "@/lib/hooks";
import { formatUsdc, formatApy, formatHealthFactor, hfTone } from "@/lib/format";
import { TxStatus } from "./TxStatus";

export function BorrowTab({ initialTier }: { initialTier: number }) {
  const { address } = useAccount();
  const [tier, setTier] = useState(initialTier);
  const [amount, setAmount] = useState("");
  const [showBreakdown, setShowBreakdown] = useState(false);
  const { position } = useUserPosition(address as Address);
  const maxBorrow = useMaxBorrowable(address as Address, tier);
  const borrowAprs = useBorrowAprs();

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
  const grossYield = borrowApr !== undefined ? borrowApr * utilFactor() : undefined;

  function utilFactor() {
    return 0.5; // demo utilization factor
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
                  : "border-border text-slate-400 hover:border-accent"
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

      <div className="space-y-1 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-400">Borrow APR (tier {tier})</span>
          <span className="text-slate-100">{formatApy(borrowApr)}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-400">Max LTV</span>
          <span className="text-slate-100">{cfg.ltv}%</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-400">LTV after borrow</span>
          <span className={projLtv > cfg.ltv ? "text-danger" : "text-slate-100"}>
            {projLtv.toFixed(2)}%
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-400">Health Factor after</span>
          <span className={hfTone(projHfBig) === "danger" ? "text-danger" : "text-slate-100"}>
            {formatHealthFactor(projHfBig)}
          </span>
        </div>
      </div>

      {/* Yield breakdown */}
      <div>
        <button
          className="text-sm text-accentlight hover:underline"
          onClick={() => setShowBreakdown((v) => !v)}
        >
          {showBreakdown ? "▾" : "▸"} Yield breakdown (estimated)
        </button>
        {showBreakdown && grossYield !== undefined && (
          <div className="mt-2 space-y-1 rounded-lg bg-bg p-3 text-sm">
            <Row k="Gross Yield" v={`~${grossYield.toFixed(2)}%`} />
            <Row k="Expected Loss" v={`~${(grossYield * 0.12).toFixed(2)}%`} />
            <Row k="Protocol Fee" v={`~${(grossYield * 0.03).toFixed(2)}%`} />
            <Row k="Reserve" v={`~${(grossYield * 0.05).toFixed(2)}%`} />
            <Row k="Estimated Net APY" v={formatApy(grossYield * 0.8)} accent />
            <p className="text-[11px] text-slate-600">
              Estimates only — not a guarantee of return.
            </p>
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

      <div className="border-t border-border pt-3 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-400">Current debt</span>
          <span className="text-slate-100">{formatUsdc(debt / BigInt(1e12))}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-400">Current tier</span>
          <span className="text-slate-100">
            {position && position.tier > 0n ? `Tier ${Number(position.tier)}` : "None"}
          </span>
        </div>
      </div>
    </div>
  );
}

function Row({ k, v, accent }: { k: string; v: string; accent?: boolean }) {
  return (
    <div className="flex justify-between">
      <span className="text-slate-400">{k}</span>
      <span className={accent ? "text-success" : "text-slate-100"}>{v}</span>
    </div>
  );
}
