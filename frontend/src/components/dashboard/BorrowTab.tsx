"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { LendingPoolAbi } from "@/lib/abis";
import { ADDRESSES, MIN_BORROW, TIERS, COLLATERALS, COLLATERAL_TIER_LTV, COLLATERAL_TIER_LT, TX_GAS, type MarketInfo } from "@/lib/config";
import { useUserPositionV2, useMarketStats, useMarketBorrowAprs, useAssetPrices, useInvalidateAllOnTxSuccess } from "@/lib/hooks";
import { formatToken, formatHealthFactor, numToRaw, rawToNum } from "@/lib/format";
import { borrowAprAt, borrowAprUpperPct } from "@/lib/rates";
import { YieldBreakdown } from "@/components/YieldBreakdown";
import { TxStatus } from "./TxStatus";

export function BorrowTab({ market, initialTier }: { market: MarketInfo; initialTier: number }) {
  const { address } = useAccount();
  const [tier, setTier] = useState(initialTier);
  const [amount, setAmount] = useState("");
  const [showBreakdown, setShowBreakdown] = useState(false);
  const { position } = useUserPositionV2(address as Address);
  const { stats } = useMarketStats(market.id);
  const borrowAprs = useMarketBorrowAprs(market.id);
  const collTokens = COLLATERALS.map((c) => c.address);
  const prices = useAssetPrices([...collTokens, market.address]);

  const { data: hash, isPending, isSuccess, writeContract } = useWriteContract();
  useInvalidateAllOnTxSuccess(isSuccess);

  const cfg = TIERS.find((t) => t.tier === tier)!;
  const collBalances = COLLATERALS.map((c) =>
    position ? rawToNum(position.collateral[c.id] ?? 0n, c.decimals) : 0,
  );
  const collValues = collBalances.map((bal, i) => bal * (prices[COLLATERALS[i].address] ?? 0));
  const collValueUsd = collValues.reduce((a, b) => a + b, 0);
  // Contract: capacity = Σ value_i × maxLTV(coll_i, tier)
  const capacityUsd = collValues.reduce(
    (sum, val, i) => sum + val * (COLLATERAL_TIER_LTV[COLLATERALS[i].symbol][tier - 1] / 100),
    0,
  );
  // Contract HF numerator = Σ value_i × LT(coll_i, tier)
  const weightedLtUsd = collValues.reduce(
    (sum, val, i) => sum + val * (COLLATERAL_TIER_LT[COLLATERALS[i].symbol][tier - 1] / 100),
    0,
  );

  const amountNum = parseFloat(amount);
  const raw = numToRaw(amountNum, market.decimals);
  const debtUsd = position ? Number(position.debtWad) / 1e18 : 0;
  const amountUsd = amountNum * (prices[market.address] ?? 1);
  const newDebtUsd = debtUsd + amountUsd;
  const maxRaw =
    capacityUsd > debtUsd
      ? numToRaw((capacityUsd - debtUsd) / (prices[market.address] ?? 1), market.decimals)
      : 0n;

  const projLtv = collValueUsd > 0 ? (newDebtUsd / collValueUsd) * 100 : 0;
  const projHf = weightedLtUsd > 0 && newDebtUsd > 0 ? weightedLtUsd / newDebtUsd : 0;
  const projHfBig = projHf > 0 ? BigInt(Math.floor(projHf * 1e18)) : 0n;

  const tierLocked = position && position.tier > 0n && Number(position.tier) !== tier;
  const valid = amountNum >= MIN_BORROW && raw > 0n && raw <= maxRaw && !tierLocked && collValueUsd > 0;

  const borrowApr = borrowAprs[tier];
  const utilPct = stats ? (Number(stats.utilization) / 1e18) * 100 : 0;
  const rangeLow = borrowAprAt(Math.max(0, utilPct - 10), tier);
  const rangeHigh = borrowAprAt(Math.min(100, utilPct + 10), tier);
  const range7dLow = Math.max(0, rangeLow - 0.3);
  const range7dHigh = rangeHigh + 0.3;
  const utilFactor = utilPct > 0 ? utilPct / 100 : 0.5;
  const grossYield = borrowApr !== undefined ? borrowApr * utilFactor : undefined;

  return (
    <div className="space-y-4">
      <div className="rounded-lg bg-warning/10 px-3 py-2 text-xs text-warning">
        Positions with Health Factor below 1.0 may be liquidated by third parties. Liquidation is a
        core mechanism that protects the protocol and all depositors. Monitor your position health
        regularly.
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
          {cfg.label} · Higher LTV = greater capital efficiency, but higher liquidation risk and
          higher interest rates. Select a tier aligned with your risk tolerance. LTV/LT limits are
          applied per collateral asset (WBTC uses a conservative table).
        </p>
      </div>

      {tierLocked && (
        <p className="text-xs text-danger">
          You already borrowed at tier {Number(position?.tier)}. Repay in full to switch tiers.
        </p>
      )}

      <div>
        <label className="label">Borrow amount ({market.symbol})</label>
        <input
          type="number"
          className="input"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        <p className="mt-1 text-xs text-slate-500">
          Min {MIN_BORROW} {market.symbol} · Max borrowable: {formatToken(maxRaw, market.decimals)}{" "}
          {market.symbol}
        </p>
      </div>

      <div className="rounded-lg bg-sky-50 px-3 py-2 text-xs text-sky-700 ring-1 ring-sky-200">
        Interest rates are variable and adjust in real time with pool utilization. Your actual
        borrowing cost may differ from the rate shown at the time of borrowing. Choose your risk
        tier carefully.
      </div>

      <div className="space-y-1 text-sm">
        <div className="flex justify-between">
          <span className="text-slate-500">Borrow APR · Tier {tier}</span>
          <span className="font-semibold text-slate-800">
            {borrowApr !== undefined ? `~${borrowApr.toFixed(2)}%` : "--"} now · up to ~
            {borrowAprUpperPct(tier).toFixed(1)}% at high utilization
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">7D Range (est.)</span>
          <span className="text-slate-800">
            {range7dLow.toFixed(2)}% – {range7dHigh.toFixed(2)}%
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Utilization ({market.symbol})</span>
          <span className="text-slate-800">{utilPct.toFixed(2)}%</span>
        </div>
        <p className="pt-1 text-[11px] text-slate-400">
          Rates are variable. "Up to" assumes ~90% utilization; 7D ranges are estimated from the
          current rate model — not historical data.
        </p>
        <div className="flex justify-between">
          <span className="text-slate-500">Collateral value (all)</span>
          <span className="text-slate-800">${collValueUsd.toLocaleString("en-US", { maximumFractionDigits: 2 })}</span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Max borrowable (weighted LTV)</span>
          <span className="text-slate-800">
            {formatToken(maxRaw, market.decimals)} {market.symbol}
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">LTV after borrow</span>
          <span className={projLtv > cfg.ltv ? "text-danger" : "text-slate-800"}>
            {projLtv.toFixed(2)}%
          </span>
        </div>
        <div className="flex justify-between">
          <span className="text-slate-500">Health Factor after</span>
          <span className="text-slate-800">{formatHealthFactor(projHfBig)}</span>
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
            args: [BigInt(market.id), raw, BigInt(tier)],
gas: TX_GAS,
          })
        }
      >
        {isPending ? "Borrowing…" : `Borrow ${market.symbol}`}
      </button>
      <TxStatus hash={hash} />
    </div>
  );
}
