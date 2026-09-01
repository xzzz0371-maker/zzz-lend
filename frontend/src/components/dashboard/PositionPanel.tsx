"use client";

import { UserPosition } from "@/lib/hooks";
import { TIERS } from "@/lib/config";
import { formatEth, formatUsdc, formatWadPct, formatHealthFactor, hfTone } from "@/lib/format";

const toneText: Record<"success" | "warning" | "danger", string> = {
  success: "text-success",
  warning: "text-warning",
  danger: "text-danger",
};

export function PositionPanel({ position }: { position?: UserPosition }) {
  if (!position) {
    return (
      <div className="card p-5">
        <h2 className="mb-3 text-lg font-semibold text-slate-100">Your Position</h2>
        <p className="text-sm text-slate-500">
          Connect your wallet and supply collateral or borrow to see your position here.
        </p>
      </div>
    );
  }

  const collateralEth = Number(position.collateral) / 1e18;
  const collateralUsd = Number(position.collateralValue) / 1e18;
  const debtUsdc = Number(position.debt) / 1e18;
  const tier = Number(position.tier);
  const cfg = TIERS.find((t) => t.tier === tier);
  const ltvPct = collateralUsd > 0 ? (debtUsdc / collateralUsd) * 100 : 0;
  const hf = position.healthFactor;
  const hfToneResult = hfTone(position.healthFactor);
  const hfColor = toneText[hfToneResult];

  return (
    <div className="card p-5">
      <h2 className="mb-4 text-lg font-semibold text-slate-100">Your Position</h2>
      <dl className="space-y-3 text-sm">
        <div className="flex justify-between">
          <dt className="text-slate-400">Collateral</dt>
          <dd className="text-slate-100">
            {formatEth(position.collateral)} ETH{" "}
            <span className="text-slate-500">(${collateralUsd.toLocaleString("en-US", { maximumFractionDigits: 2 })})</span>
          </dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-slate-400">Debt</dt>
          <dd className="text-slate-100">{debtUsdc.toLocaleString("en-US", { maximumFractionDigits: 2 })} USDC</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-slate-400">Current LTV</dt>
          <dd className="text-slate-100">{formatAmountPct(ltvPct)}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-slate-400">Max LTV</dt>
          <dd className="text-slate-100">{cfg ? `${cfg.ltv}%` : "--"}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-slate-400">Liquidation Threshold</dt>
          <dd className="text-slate-100">{cfg ? `${cfg.lt}%` : "--"}</dd>
        </div>
        <div className="flex justify-between items-center">
          <dt className="text-slate-400">Health Factor</dt>
          <dd className={`text-lg font-semibold ${hfColor}`}>{formatHealthFactor(hf)}</dd>
        </div>
        <div className="flex justify-between">
          <dt className="text-slate-400">Current Tier</dt>
          <dd className="text-slate-100">
            {cfg ? `${cfg.label}` : "No active borrow"}
          </dd>
        </div>
      </dl>
      {position.liquidatable && (
        <div className="mt-3 rounded-lg bg-danger/15 px-3 py-2 text-sm text-danger">
          Your position is liquidatable. Add collateral or repay immediately.
        </div>
      )}
    </div>
  );
}

function formatAmountPct(n: number) {
  return `${n.toLocaleString("en-US", { maximumFractionDigits: 2 })}%`;
}
