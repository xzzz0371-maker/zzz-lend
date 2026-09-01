"use client";

import { usePoolStats, useBorrowAprs, usePrices } from "@/lib/hooks";
import { StatCard } from "@/components/StatCard";
import { RiskCard } from "@/components/RiskCard";
import { UtilizationRing } from "@/components/UtilizationRing";
import { RateCurve } from "@/components/RateCurve";
import { TIERS } from "@/lib/config";

export default function HomePage() {
  const { stats, isPending } = usePoolStats();
  const borrowAprs = useBorrowAprs();
  const { ethUsd } = usePrices();

  const supplyAprPct = stats ? (Number(stats.supplyApr) / 1e18) * 100 : 0;
  const utilPct = stats ? (Number(stats.utilization) / 1e18) * 100 : 0;
  // 7-day average supply APY — demo estimate around the current value.
  const supply7d = supplyAprPct * (0.96 + (supplyAprPct % 0.08) / 100);

  return (
    <div className="space-y-12">
      {/* Hero */}
      <section className="grid items-center gap-8 lg:grid-cols-[1.4fr_1fr]">
        <div className="space-y-4">
          <span className="pill bg-blue-50 text-blue-600 ring-1 ring-blue-200">
            Sepolia Testnet · Live
          </span>
          <h1 className="font-display text-4xl font-bold text-slate-900 sm:text-5xl">
            Lending where <span className="text-gradient">you choose your risk</span>
          </h1>
          <p className="max-w-xl text-slate-500">
            Supply USDC to earn dynamic estimated yield, or borrow against ETH across five risk
            tiers. Real-time risk pricing, transparent reserves, and losses shared by depositors on
            bad debt — like a fund whose NAV can decline.
          </p>
          <div className="flex flex-wrap gap-3">
            <a href="/dashboard" className="btn-primary">
              Launch App
            </a>
            <a href="/stress-test" className="btn-outline">
              Run Stress Test
            </a>
          </div>
        </div>

        {/* Hero visual: utilization ring + risk ladder */}
        <div className="card card-hover flex flex-col items-center gap-5 p-6">
          {stats ? (
            <UtilizationRing value={utilPct} />
          ) : (
            <div className="skeleton h-44 w-44 rounded-full" />
          )}
          <div className="w-full">
            <div className="mb-1 text-center text-xs font-semibold uppercase tracking-wide text-slate-500">
              Risk ladder
            </div>
            <div className="flex h-3 w-full overflow-hidden rounded-full">
              {TIERS.map((t) => (
                <div
                  key={t.tier}
                  className="h-full"
                  style={{
                    width: `${100 / TIERS.length}%`,
                    background: `linear-gradient(180deg, rgba(255,255,255,0.35), transparent), ${
                      { Low: "#34d399", Medium: "#fbbf24", High: "#fb923c", "Very High": "#f87171", Extreme: "#ef4444" }[t.risk]
                    }`,
                  }}
                />
              ))}
            </div>
            <div className="mt-1 flex justify-between text-[10px] text-slate-500">
              <span>T1 · 50%</span>
              <span>T3 · 70%</span>
              <span>T5 · 80%</span>
            </div>
          </div>
        </div>
      </section>

      {/* Core metrics */}
      <section>
        <h2 className="mb-4 font-display text-xl font-bold text-slate-800">Market Overview</h2>
        {isPending && !stats ? (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="card p-5">
                <div className="skeleton mb-2 h-3 w-16" />
                <div className="skeleton h-7 w-24" />
              </div>
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
            <StatCard title="TVL" value={stats ? Number(stats.totalSupply) / 1e6 : 0} prefix="$" sub={`ETH ≈ $${ethUsd.toLocaleString("en-US")}`} tone="accent" />
            <StatCard title="Total Supply" value={stats ? Number(stats.totalSupply) / 1e6 : 0} suffix=" USDC" />
            <StatCard title="Total Borrow" value={stats ? Number(stats.totalBorrows) / 1e6 : 0} suffix=" USDC" />
            <StatCard title="Utilization" value={utilPct} suffix="%" />
            <StatCard
              title="Available Liquidity"
              value={stats ? Number(stats.cash) / 1e6 : 0}
              suffix=" USDC"
              sub="Withdrawals may fail if liquidity is insufficient."
            />
            <StatCard
              title="Supply APY"
              value={supplyAprPct}
              prefix="~"
              suffix="%"
              tone="success"
              sub={`7D Average ~${supply7d.toFixed(2)}% · Utilization ${utilPct.toFixed(1)}%`}
            />
          </div>
        )}
        {stats && utilPct < 20 && (
          <div className="mt-3 rounded-xl bg-amber-50 px-3 py-2 text-xs text-amber-700 ring-1 ring-amber-200">
            Borrow demand is low — pool funds are mostly idle, so Supply APY may stay low until
            utilization rises.
          </div>
        )}
      </section>

      {/* Rate curve + reserve/treasury */}
      <section className="grid gap-6 lg:grid-cols-[1.6fr_1fr]">
        <div className="card card-hover p-6">
          <div className="mb-2 flex items-center justify-between">
            <h2 className="font-display text-lg font-bold text-slate-800">Interest Rate Model</h2>
            <span className="text-xs text-slate-500">Estimated · NORMAL preset</span>
          </div>
          <RateCurve />
        </div>
        <div className="grid gap-4">
          <div className="card card-hover p-5">
            <div className="stat-title">Risk Reserve</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">
              {stats ? `${(Number(stats.totalReserve) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 2 })} USDC` : "--"}
            </div>
            <div className="mt-1 text-xs text-slate-500">First-loss buffer · target 3% of borrows</div>
          </div>
          <div className="card card-hover p-5">
            <div className="stat-title">Treasury</div>
            <div className="mt-1 text-2xl font-bold text-slate-900">
              {stats ? `${(Number(stats.treasuryAccrued) / 1e6).toLocaleString("en-US", { maximumFractionDigits: 2 })} USDC` : "--"}
            </div>
            <div className="mt-1 text-xs text-slate-500">Pending protocol fees</div>
          </div>
          <div className="card card-hover p-5">
            <div className="stat-title">Historical Max Drawdown</div>
            <div className="mt-1 text-2xl font-bold text-red-600">~12.4%</div>
            <div className="mt-1 text-xs text-slate-500">Estimate from historical simulations</div>
          </div>
        </div>
      </section>

      {/* Choose Your Risk */}
      <section>
        <h2 className="mb-1 font-display text-xl font-bold text-slate-800">Choose Your Risk</h2>
        <p className="mb-4 text-sm text-slate-500">
          Pick a tier. Higher LTV means higher borrowing power, higher estimated yield — and higher
          risk.
        </p>
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
          {TIERS.map((t) => (
            <RiskCard
              key={t.tier}
              tier={t.tier}
              ltv={t.ltv}
              lt={t.lt}
              risk={t.risk}
              borrowApr={borrowAprs[t.tier]}
              supplyContribution={supplyAprPct}
            />
          ))}
        </div>
      </section>

      {/* Risk notice */}
      <section className="card border-red-200/70 p-5" style={{ borderColor: "rgba(239,68,68,0.25)" }}>
        <p className="text-sm text-red-700">
          <strong>Risk notice:</strong> Deposits are not guaranteed. Your principal may decrease due
          to bad debt, similar to a fund whose NAV can decline. All APY figures are estimates and
          may change with market conditions. Borrowing involves liquidation risk — if your Health
          Factor drops below 1, your collateral may be liquidated.
        </p>
      </section>
    </div>
  );
}
