"use client";

import Link from "next/link";
import { RISK_COLOR, TIERS } from "@/lib/config";

export function RiskCard({
  tier,
  ltv,
  lt,
  risk,
  borrowApr,
  supplyContribution,
  highlight,
}: {
  tier: number;
  ltv: number;
  lt: number;
  risk: string;
  borrowApr?: number;
  supplyContribution?: number;
  highlight?: boolean;
}) {
  const color = RISK_COLOR[risk] ?? "#60a5fa";
  return (
    <Link
      href={`/dashboard?tier=${tier}`}
      className={`card group relative flex flex-col gap-3 p-4 transition-colors hover:border-accent ${
        highlight ? "border-accent" : ""
      }`}
    >
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold text-slate-100">Tier {tier}</span>
        <span
          className="rounded-full px-2 py-0.5 text-xs font-medium"
          style={{ backgroundColor: `${color}22`, color }}
        >
          {risk}
        </span>
      </div>
      <div className="text-2xl font-bold text-white">{ltv}%</div>
      <div className="text-xs text-slate-500">Max LTV · Liq. threshold {lt}%</div>
      <div className="mt-1 space-y-1 border-t border-border pt-2 text-xs">
        {borrowApr !== undefined && (
          <div className="flex justify-between">
            <span className="text-slate-400">Borrow APR</span>
            <span className="text-slate-100">~{borrowApr.toFixed(2)}%</span>
          </div>
        )}
        {supplyContribution !== undefined && (
          <div className="flex justify-between">
            <span className="text-slate-400">Supply APY contribution</span>
            <span className="text-slate-100">~{supplyContribution.toFixed(2)}%</span>
          </div>
        )}
      </div>
      <div className="text-[11px] text-slate-600">Estimated, not guaranteed</div>
    </Link>
  );
}
