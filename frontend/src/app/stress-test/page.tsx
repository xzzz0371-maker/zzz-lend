"use client";

import { useMemo, useState } from "react";
import { type Address } from "viem";
import { useAccount } from "wagmi";
import { TIERS } from "@/lib/config";
import { useUserPosition, usePoolStats, usePrices } from "@/lib/hooks";
import { formatEth } from "@/lib/format";

const DROPS = [10, 20, 30, 40, 50];

function statusOf(hf: number): "safe" | "warning" | "liquidatable" {
  if (hf >= 1.5) return "safe";
  if (hf >= 1) return "warning";
  return "liquidatable";
}

const STATUS_STYLE: Record<string, string> = {
  safe: "bg-success/15 text-success",
  warning: "bg-warning/15 text-warning",
  liquidatable: "bg-danger/15 text-danger",
};

export default function StressTestPage() {
  const { address, isConnected } = useAccount();
  const { position } = useUserPosition(address as Address);
  const { stats } = usePoolStats();
  const { ethUsd } = usePrices();
  const [drop, setDrop] = useState(30);

  // Use the user's real position if present, otherwise a demo position.
  const collateralEth = position ? Number(position.collateral) / 1e18 : 10;
  const debtUsdc = position ? Number(position.debt) / 1e18 : 24000;
  const tier = position && position.tier > 0n ? Number(position.tier) : 5;
  const cfg = TIERS.find((t) => t.tier === tier)!;

  const priceAfter = ethUsd * (1 - drop / 100);
  const collateralUsd = collateralEth * ethUsd;
  const collateralUsdAfter = collateralEth * priceAfter;
  const ltvAfter = (debtUsdc / collateralUsdAfter) * 100;
  const hfAfter = (collateralUsdAfter * (cfg.lt / 100)) / debtUsdc;
  const status = statusOf(hfAfter);
  const estLoss = status === "liquidatable" ? Math.max(0, debtUsdc - collateralUsdAfter) : 0;

  const reserveCoverage = stats && Number(stats.totalBorrows) > 0 ? (Number(stats.totalReserve) / Number(stats.totalBorrows)) * 100 : 0;

  // Pool-wide depositor loss estimate (demo): if aggregate collateral drops below borrows.
  const poolBorrowUsd = stats ? Number(stats.totalBorrows) / 1e6 : 0;
  // Estimate pool aggregate collateral via utilization proxy (demo): assume LTV≈50% of borrows.
  const poolCollateralUsd = poolBorrowUsd * 2;
  const poolCollateralAfter = poolCollateralUsd * (1 - drop / 100);
  const poolShortfall = Math.max(0, poolBorrowUsd - poolCollateralAfter * 0.78);
  const depositorLossPct = poolBorrowUsd > 0 ? Math.min(100, (poolShortfall / poolBorrowUsd) * 100) : 0;

  const table = useMemo(() => {
    const rows: { tier: number; ltv: number; lt: number }[] = TIERS;
    return rows.map((r) => ({
      ...r,
      cells: DROPS.map((d) => {
        const pa = ethUsd * (1 - d / 100);
        const cv = collateralEth * pa;
        // Use each tier's own borrow amount at max LTV for the table.
        const debtForTier = collateralUsd * (r.ltv / 100);
        const hf = cv * (r.lt / 100) / (debtForTier || 1);
        return statusOf(hf);
      }),
    }));
  }, [collateralEth, collateralUsd, ethUsd]);

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-white">Stress Test</h1>
        <p className="mt-1 text-sm text-slate-400">
          Simulate an ETH price drop and see how your position and the pool react. This is an
          off-chain simulation — nothing is broadcast.
        </p>
      </div>

      {/* Controls */}
      <div className="card p-5">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <label className="label">ETH price drop</label>
            <div className="flex gap-2">
              {DROPS.map((d) => (
                <button
                  key={d}
                  onClick={() => setDrop(d)}
                  className={`rounded-lg border px-3 py-2 text-sm ${
                    drop === d
                      ? "border-accent bg-accent/10 text-white"
                      : "border-border text-slate-400 hover:border-accent"
                  }`}
                >
                  -{d}%
                </button>
              ))}
            </div>
          </div>
          <div className="text-sm text-slate-400">
            Current ETH: <span className="text-slate-100">${ethUsd.toLocaleString("en-US")}</span> →{" "}
            <span className="text-danger">${priceAfter.toLocaleString("en-US")}</span>
          </div>
        </div>
        {!isConnected && (
          <p className="mt-3 text-xs text-slate-500">
            Not connected — showing a demo position (10 ETH collateral, ~80% LTV at tier 5).
          </p>
        )}
      </div>

      {/* Simulation output */}
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Metric label="Collateral value" value={`$${collateralUsdAfter.toLocaleString("en-US", { maximumFractionDigits: 0 })}`} sub={`from $${collateralUsd.toLocaleString("en-US", { maximumFractionDigits: 0 })}`} />
        <Metric label="LTV after" value={`${ltvAfter.toFixed(2)}%`} tone={ltvAfter > cfg.ltv ? "danger" : undefined} />
        <Metric label="Health Factor" value={hfAfter.toFixed(2)} tone={status === "safe" ? "success" : status === "warning" ? "warning" : "danger"} />
        <Metric label="Liquidation status" value={status === "safe" ? "Safe" : status === "warning" ? "At Risk" : "Liquidatable"} tone={status === "safe" ? "success" : status === "warning" ? "warning" : "danger"} />
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <Metric label="Estimated loss if liquidated" value={`$${estLoss.toLocaleString("en-US", { maximumFractionDigits: 0 })}`} tone={estLoss > 0 ? "danger" : "success"} />
        <Metric label="Reserve coverage" value={`${reserveCoverage.toFixed(2)}%`} sub="of total borrows" />
        <Metric label="Depositor loss estimate (pool)" value={`~${depositorLossPct.toFixed(1)}%`} tone={depositorLossPct > 0 ? "danger" : "success"} sub="demo — fund NAV can decline" />
      </div>

      {/* Tier comparison table */}
      <div>
        <h2 className="mb-3 text-lg font-semibold text-slate-100">
          Tier comparison — {formatEth(BigInt(Math.floor(collateralEth * 1e18)))} ETH collateral
        </h2>
        <div className="card overflow-x-auto p-4">
          <table className="w-full text-center text-sm">
            <thead>
              <tr className="text-slate-400">
                <th className="px-3 py-2 text-left">Tier</th>
                {DROPS.map((d) => (
                  <th key={d} className="px-3 py-2">
                    -{d}%
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {table.map((r) => (
                <tr key={r.tier} className="border-t border-border">
                  <td className="px-3 py-2 text-left text-slate-300">
                    T{r.tier} · LTV {r.ltv}%
                  </td>
                  {r.cells.map((s, i) => (
                    <td key={i} className="px-3 py-2">
                      <span className={`inline-block rounded-full px-2 py-1 text-xs ${STATUS_STYLE[s]}`}>
                        {s === "safe" ? "Safe" : s === "warning" ? "At Risk" : "Liquidatable"}
                      </span>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="mt-2 text-xs text-slate-500">
          Simulation only. Health Factor &lt; 1 means liquidation may occur.
        </p>
      </div>
    </div>
  );
}

function Metric({
  label,
  value,
  sub,
  tone,
}: {
  label: string;
  value: string;
  sub?: string;
  tone?: "success" | "warning" | "danger" | "default";
}) {
  const cls =
    tone === "success"
      ? "text-success"
      : tone === "warning"
        ? "text-warning"
        : tone === "danger"
          ? "text-danger"
          : "text-slate-100";
  return (
    <div className="card p-4">
      <div className="stat-title">{label}</div>
      <div className={`mt-1 text-lg font-semibold ${cls}`}>{value}</div>
      {sub && <div className="mt-0.5 text-xs text-slate-500">{sub}</div>}
    </div>
  );
}
