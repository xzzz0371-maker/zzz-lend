"use client";

import { CountUp } from "./CountUp";

export function StatCard({
  title,
  value,
  decimals = 2,
  prefix = "",
  suffix = "",
  sub,
  tone = "default",
}: {
  title: string;
  value: number;
  decimals?: number;
  prefix?: string;
  suffix?: string;
  sub?: string;
  tone?: "default" | "success" | "warning" | "danger" | "accent";
}) {
  const toneClass =
    tone === "success"
      ? "text-emerald-600"
      : tone === "warning"
        ? "text-amber-600"
        : tone === "danger"
          ? "text-red-600"
          : tone === "accent"
            ? "text-accent"
            : "text-slate-900";
  return (
    <div className="card card-hover p-5">
      <div className="stat-title">{title}</div>
      <div className={`mt-1 text-2xl font-bold ${toneClass}`}>
        <CountUp value={value} decimals={decimals} prefix={prefix} suffix={suffix} />
      </div>
      {sub && <div className="mt-1 text-xs text-slate-500">{sub}</div>}
    </div>
  );
}
