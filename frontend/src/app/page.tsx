"use client";

import { usePoolStats, useBorrowAprs, usePrices } from "@/lib/hooks";
import { StatCard } from "@/components/StatCard";
import { RiskCard } from "@/components/RiskCard";
import { TIERS } from "@/lib/config";
import { formatUsdc, formatWadPct, formatApy } from "@/lib/format";

export default function HomePage() {
  const { stats } = usePoolStats();
  const borrowAprs = useBorrowAprs();
  const { ethUsd } = usePrices();

  // Supply APY contribution per tier = supply APR × share of that tier's borrows.
  // For display we approximate each tier's contribution as supplyApr (pool-level) scaled by tier weight.
  const supplyAprPct = stats ? (Number(stats.supplyApr) / 1e18) * 100 : undefined;

  return (
    <div className="space-y-10">
      {/* Hero */}
      <section className="space-y-3">
        <h1 className="text-3xl font-bold text-white sm:text-4xl">
          Lending where <span className="text-accentlight">you choose your risk</span>
        </h1>
        <p className="max-w-2xl text-slate-400">
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
      </section>

      {/* Pool stats */}
      <section>
        <h2 className="mb-3 text-lg font-semibold text-slate-100">Market Overview</h2>
        {stats ? (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
            <StatCard
              title="TVL"
              value={`$${formatUsdc(stats.totalSupply)}`}
              sub={`ETH ≈ $${ethUsd.toLocaleString("en-US")}`}
            />
            <StatCard title="Total Supply" value={`${formatUsdc(stats.totalSupply)} USDC`} />
            <StatCard title="Total Borrow" value={`${formatUsdc(stats.totalBorrows)} USDC`} />
            <StatCard title="Utilization" value={formatWadPct(stats.utilization)} />
            <StatCard
              title="Available Liquidity"
              value={`${formatUsdc(stats.cash)} USDC`}
              sub="Withdrawals may fail if liquidity is insufficient."
            />
            <StatCard
              title="Supply APY"
              value={formatApy(supplyAprPct)}
              sub="Estimated · varies with market rates"
              tone="success"
            />
            <StatCard
              title="Risk Reserve"
              value={`${formatUsdc(stats.totalReserve)} USDC`}
              sub="First-loss buffer · target 3% of borrows"
            />
            <StatCard
              title="Treasury"
              value={`${formatUsdc(stats.treasuryAccrued)} USDC`}
              sub="Pending protocol fees"
            />
          </div>
        ) : (
          <div className="card p-6 text-sm text-slate-400">
            Loading market data from Sepolia…
          </div>
        )}
      </section>

      {/* Choose Your Risk */}
      <section>
        <h2 className="mb-1 text-lg font-semibold text-slate-100">Choose Your Risk</h2>
        <p className="mb-3 text-sm text-slate-500">
          Pick a tier. Higher LTV means higher borrowing power, higher estimated yield — and higher
          risk.
        </p>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
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
      <section className="card border-danger/40 p-4">
        <p className="text-sm text-danger">
          <strong>Risk notice:</strong> Deposits are not guaranteed. Your principal may decrease due
          to bad debt, similar to a fund whose NAV can decline. All APY figures are estimates and
          may change with market conditions. Borrowing involves liquidation risk — if your Health
          Factor drops below 1, your collateral may be liquidated.
        </p>
      </section>
    </div>
  );
}
