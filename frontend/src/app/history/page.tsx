"use client";

import { useMemo, useState } from "react";
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
} from "recharts";
import { usePoolStats, useBorrowAprs } from "@/lib/hooks";
import { ADDRESSES, ETHERSCAN_URL } from "@/lib/config";

const PERIODS = ["24H", "7D", "30D"] as const;
const POINTS = 14;

function demoSeries(base: number, period: number, seed: number): number[] {
  const out: number[] = [];
  let v = base * (0.8 + (seed % 5) / 10);
  for (let i = 0; i < POINTS; i++) {
    v = v * (1 + (Math.sin(seed + i * 1.7) * 0.05 + (period % 3) * 0.002) % 0.1);
    out.push(Math.max(0, v));
  }
  return out;
}

export default function HistoryPage() {
  const [period, setPeriod] = useState<number>(1);
  const { stats } = usePoolStats();
  const borrowAprs = useBorrowAprs();

  const data = useMemo(() => {
    const p = period + 1;
    const borrowApr = borrowAprs[5] ?? 8;
    const supplyApr = stats ? (Number(stats.supplyApr) / 1e18) * 100 : 4;
    const util = stats ? (Number(stats.utilization) / 1e18) * 100 : 20;
    const reserve = stats ? Number(stats.totalReserve) / 1e6 : 0;
    const toSeries = (base: number, seed: number) =>
      demoSeries(base, p, seed).map((v, i) => ({ label: i, value: v }));
    return [
      { title: "Average Borrow APR (T5)", series: toSeries(borrowApr, 3), unit: "%", color: "#f97316" },
      { title: "Average Supply APY", series: toSeries(supplyApr, 5), unit: "%", color: "#3b82f6" },
      { title: "Average Utilization", series: toSeries(util, 7), unit: "%", color: "#8b5cf6" },
      { title: "Total Liquidations", series: toSeries(period * 2, 11), unit: " tx", color: "#ef4444" },
      { title: "Bad Debt", series: toSeries(period * 0.8, 13), unit: " USDC", color: "#dc2626" },
      { title: "Reserve Growth", series: toSeries(reserve, 17), unit: " USDC", color: "#10b981" },
    ];
  }, [period, stats, borrowAprs]);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="font-display text-3xl font-bold text-slate-900">History</h1>
          <p className="mt-1 text-sm text-slate-500">
            Demo data — derived from current on-chain values with simulated history. Real indexed
            data arrives in a later phase.
          </p>
        </div>
        <div className="flex gap-1 rounded-xl bg-slate-200/50 p-1">
          {PERIODS.map((p, i) => (
            <button
              key={p}
              onClick={() => setPeriod(i)}
              className={`rounded-lg px-4 py-1.5 text-sm font-semibold transition-all ${
                period === i ? "bg-white text-accent shadow-sm" : "text-slate-500 hover:text-slate-800"
              }`}
            >
              {p}
            </button>
          ))}
        </div>
      </div>

      <div className="rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-700 ring-1 ring-amber-200">
        Demo data — shown for layout/UX purposes only.
      </div>

      <div className="grid gap-5 md:grid-cols-2">
        {data.map((d) => (
          <div key={d.title} className="card card-hover p-5">
            <div className="flex items-baseline justify-between">
              <h3 className="font-display text-sm font-bold text-slate-800">{d.title}</h3>
              <span className="text-xs text-slate-500">
                {PERIODS[period]} · avg{" "}
                {(d.series.reduce((a, b) => a + b.value, 0) / d.series.length).toFixed(2)}
                {d.unit}
              </span>
            </div>
            <div className="mt-3 h-32">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={d.series} margin={{ top: 4, right: 4, left: -14, bottom: 0 }}>
                  <defs>
                    <linearGradient id={`g-${d.title}`} x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={d.color} stopOpacity={0.35} />
                      <stop offset="100%" stopColor={d.color} stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(15,23,42,0.07)" vertical={false} />
                  <XAxis dataKey="label" hide />
                  <YAxis tick={{ fill: "#64748b", fontSize: 11 }} axisLine={false} tickLine={false} width={48} />
                  <Tooltip
                    formatter={(v) => [`${(v as number).toFixed(2)}${d.unit}`, undefined]}
                    contentStyle={{
                      background: "rgba(255,255,255,0.94)",
                      border: "1px solid rgba(15,23,42,0.1)",
                      borderRadius: 12,
                      fontSize: 12,
                      boxShadow: "0 8px 24px rgba(15,23,42,0.12)",
                    }}
                  />
                  <Area type="monotone" dataKey="value" stroke={d.color} strokeWidth={2} fill={`url(#g-${d.title})`} />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </div>
        ))}
      </div>

      <div className="card p-4 text-xs text-slate-500">
        Contract (live): LendingPool —{" "}
        <a className="text-accent" href={`${ETHERSCAN_URL}/address/${ADDRESSES.lendingPool}`} target="_blank" rel="noreferrer">
          {ADDRESSES.lendingPool}
        </a>
      </div>
    </div>
  );
}
