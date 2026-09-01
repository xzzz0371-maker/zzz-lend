"use client";

import { UserPosition } from "@/lib/hooks";
import { TIERS } from "@/lib/config";
import { HFBar } from "@/components/HFBar";

export function PositionPanel({ position }: { position?: UserPosition }) {
  if (!position) {
    return (
      <div className="card p-6">
        <h2 className="mb-3 font-display text-lg font-bold text-slate-800">Your Position</h2>
        <p className="text-sm text-slate-500">
          Connect your wallet and supply collateral or borrow to see your position here.
        </p>
      </div>
    );
  }

  const collateralUsd = Number(position.collateralValue) / 1e18;
  const debtUsdc = Number(position.debt) / 1e18;
  const tier = Number(position.tier);
  const cfg = TIERS.find((t) => t.tier === tier);
  const ltvPct = collateralUsd > 0 ? (debtUsdc / collateralUsd) * 100 : 0;
  const hfNum = Number(position.healthFactor) / 1e18;
  const hfDisplay = position.healthFactor > BigInt(1e30) ? Number.MAX_SAFE_INTEGER : hfNum;

  return (
    <div className="card p-6">
      <h2 className="mb-5 font-display text-lg font-bold text-slate-800">Your Position</h2>

      <div className="grid grid-cols-2 gap-4">
        <div className="rounded-xl bg-white/60 p-4 ring-1 ring-slate-200/60">
          <div className="stat-title">Collateral</div>
          <div className="mt-1 text-xl font-bold text-slate-900">
            {(Number(position.collateral) / 1e18).toLocaleString("en-US", { maximumFractionDigits: 4 })} ETH
          </div>
          <div className="text-xs text-slate-500">${collateralUsd.toLocaleString("en-US", { maximumFractionDigits: 2 })}</div>
        </div>
        <div className="rounded-xl bg-white/60 p-4 ring-1 ring-slate-200/60">
          <div className="stat-title">Debt</div>
          <div className="mt-1 text-xl font-bold text-slate-900">
            {debtUsdc.toLocaleString("en-US", { maximumFractionDigits: 2 })} USDC
          </div>
          <div className="text-xs text-slate-500">Current LTV {ltvPct.toFixed(2)}%</div>
        </div>
      </div>

      <div className="mt-4 grid grid-cols-3 gap-3 text-center">
        <div className="rounded-xl bg-white/60 p-3 ring-1 ring-slate-200/60">
          <div className="stat-title">Max LTV</div>
          <div className="mt-1 text-lg font-bold text-slate-900">{cfg ? `${cfg.ltv}%` : "--"}</div>
        </div>
        <div className="rounded-xl bg-white/60 p-3 ring-1 ring-slate-200/60">
          <div className="stat-title">Liq. Threshold</div>
          <div className="mt-1 text-lg font-bold text-slate-900">{cfg ? `${cfg.lt}%` : "--"}</div>
        </div>
        <div className="rounded-xl bg-white/60 p-3 ring-1 ring-slate-200/60">
          <div className="stat-title">Tier</div>
          <div className="mt-1 text-lg font-bold text-slate-900">
            {position.tier > 0n ? `T${Number(position.tier)} · ${cfg?.ltv}%` : "None"}
          </div>
        </div>
      </div>

      <div className="mt-5">
        <HFBar hf={hfDisplay} />
      </div>

      {position.liquidatable && (
        <div className="mt-3 rounded-xl bg-red-50 px-3 py-2 text-sm text-red-700 ring-1 ring-red-200">
          Your position is liquidatable. Add collateral or repay immediately.
        </div>
      )}
    </div>
  );
}
