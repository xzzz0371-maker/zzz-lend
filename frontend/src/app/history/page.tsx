"use client";

import { useMemo, useState } from "react";
import { usePoolStats, useBorrowAprs } from "@/lib/hooks";
import { ADDRESSES, ETHERSCAN_URL } from "@/lib/config";

const PERIODS = ["24H", "7D", "30D"] as const;
const POINTS = 12;

function demoSeries(base: number, period: number, seed: number): number[] {
  const out: number[] = [];
  let v = base * (0.8 + (seed % 5) / 10);
  for (let i = 0; i < POINTS; i++) {
    v = v * (1 + ((Math.sin(seed + i * 1.7) * 0.05 + (period % 3) * 0.002) % 0.1));
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
    return {
      borrowApr: demoSeries(borrowApr, p, 3),
      supplyApr: demoSeries(supplyApr, p, 5),
      util: demoSeries(util, p, 7),
      liquidations: demoSeries(period * 2, p, 11),
      badDebt: demoSeries(period * 0.8, p, 13),
      reserve: demoSeries(reserve, p, 17),
    };
  }, [period, stats, borrowAprs]);

  const avg = (arr: number[]) => arr.reduce((a, b) => a + b, 0) / arr.length;
  const max = (arr: number[]) => Math.max(...arr, 1);

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-white">History</h1>
          <p className="mt-1 text-sm text-slate-400">
            Demo data — derived from current on-chain values with simulated history. Real indexed
            data arrives in a later phase.
          </p>
        </div>
        <div className="flex gap-1">
          {PERIODS.map((p, i) => (
            <button
              key={p}
              onClick={() => setPeriod(i)}
              className={`rounded-lg border px-3 py-1.5 text-sm ${
                period === i ? "border-accent bg-accent/10 text-white" : "border-border text-slate-400"
              }`}
            >
              {p}
            </button>
          ))}
        </div>
      </div>

      <div className="rounded-lg bg-warning/10 px-3 py-2 text-xs text-warning">
        Demo data — shown for layout/UX purposes only.
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <Chart title={`Average Borrow APR (T5) · ${PERIODS[period]}`} unit="%" series={data.borrowApr} max={max(data.borrowApr)} avg={avg(data.borrowApr)} />
        <Chart title={`Average Supply APY · ${PERIODS[period]}`} unit="%" series={data.supplyApr} max={max(data.supplyApr)} avg={avg(data.supplyApr)} />
        <Chart title={`Average Utilization · ${PERIODS[period]}`} unit="%" series={data.util} max={max(data.util)} avg={avg(data.util)} />
        <Chart title={`Total Liquidations · ${PERIODS[period]}`} unit=" tx" series={data.liquidations} max={max(data.liquidations)} avg={avg(data.liquidations)} />
        <Chart title={`Bad Debt · ${PERIODS[period]}`} unit=" USDC" series={data.badDebt} max={max(data.badDebt)} avg={avg(data.badDebt)} />
        <Chart title={`Reserve Growth · ${PERIODS[period]}`} unit=" USDC" series={data.reserve} max={max(data.reserve)} avg={avg(data.reserve)} />
      </div>

      <div className="card p-4 text-xs text-slate-500">
        Contract (live): LendingPool —{" "}
        <a className="text-accentlight" href={`${ETHERSCAN_URL}/address/${ADDRESSES.lendingPool}`} target="_blank" rel="noreferrer">
          {ADDRESSES.lendingPool}
        </a>
      </div>
    </div>
  );
}

function Chart({
  title,
  unit,
  series,
  max,
  avg,
}: {
  title: string;
  unit: string;
  series: number[];
  max: number;
  avg: number;
}) {
  return (
    <div className="card p-4">
      <div className="flex items-baseline justify-between">
        <h3 className="text-sm font-semibold text-slate-100">{title}</h3>
        <span className="text-xs text-slate-400">avg {avg.toFixed(2)}{unit}</span>
      </div>
      <div className="mt-3 flex h-28 items-end gap-1">
        {series.map((v, i) => (
          <div
            key={i}
            className="flex-1 rounded-t bg-accent/70 transition-colors hover:bg-accentlight"
            style={{ height: `${Math.max(4, (v / max) * 100)}%` }}
            title={`${v.toFixed(2)}${unit}`}
          />
        ))}
      </div>
      <div className="mt-1 flex justify-between text-[10px] text-slate-600">
        <span>now</span>
        <span>{PERIODS_LABEL}</span>
      </div>
    </div>
  );
}

const PERIODS_LABEL = "→";
