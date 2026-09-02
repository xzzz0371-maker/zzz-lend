"use client";

import Link from "next/link";
import { RISK_COLOR, TIERS } from "@/lib/config";
import { CountUp } from "./CountUp";

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
  const color = RISK_COLOR[risk] ?? "#3b82f6";
  return (
    <Link
      href={`/dashboard?tier=${tier}`}
      className={`card card-hover relative flex flex-col gap-3 overflow-hidden p-4 ${
        highlight ? "ring-2 ring-accent/60" : ""
      }`}
      style={{ background: `linear-gradient(180deg, rgba(255,255,255,0.7), rgba(255,255,255,0.5))` }}
    >
      <div className="pointer-events-none absolute inset-x-0 top-0 h-1" style={{ background: color }} />
      <div className="flex items-center justify-between">
        <span className="font-display text-sm font-semibold text-slate-800">Tier {tier}</span>
        <span
          className="rounded-full px-2 py-0.5 text-xs font-semibold"
          style={{ backgroundColor: `${color}1a`, color }}
        >
          {risk}
        </span>
      </div>
      <div className="text-3xl font-bold" style={{ color }}>
        <CountUp value={ltv} suffix="%" />
      </div>
      <div className="text-xs text-slate-500">Max LTV · Liq. threshold {lt}%</div>
      <div className="mt-1 space-y-1 border-t border-slate-200/70 pt-2 text-xs">
        {borrowApr !== undefined && (
          <div className="flex justify-between">
            <span className="text-slate-500">Borrow APR</span>
            <span className="font-semibold text-slate-800">
              ~<CountUp value={borrowApr} decimals={2} suffix="%" />
            </span>
          </div>
        )}
        {supplyContribution !== undefined && (
          <div className="flex justify-between">
            <span className="text-slate-500">Supply APY contribution</span>
            <span className="font-semibold text-slate-800">
              ~<CountUp value={supplyContribution} decimals={2} suffix="%" />
            </span>
          </div>
        )}
      </div>
      <div className="text-[11px] text-slate-500">Projected, not guaranteed</div>
    </Link>
  );
}
