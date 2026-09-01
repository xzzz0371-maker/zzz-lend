"use client";

import { CountUp } from "./CountUp";

export function UtilizationRing({
  value,
  size = 180,
  stroke = 14,
}: {
  value: number; // 0-100
  size?: number;
  stroke?: number;
}) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const filled = Math.min(100, Math.max(0, value));
  const color =
    filled >= 90
      ? "#ef4444"
      : filled >= 75
        ? "#f59e0b"
        : filled >= 50
          ? "#3b82f6"
          : "#10b981";

  return (
    <div className="relative inline-flex items-center justify-center" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgba(15,23,42,0.08)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={`${(filled / 100) * c} ${c}`}
          style={{ transition: "stroke-dasharray 0.8s ease, stroke 0.4s ease" }}
        />
      </svg>
      <div className="absolute text-center">
        <div className="text-3xl font-bold" style={{ color }}>
          <CountUp value={filled} decimals={2} suffix="%" />
        </div>
        <div className="text-xs text-slate-500">Utilization</div>
      </div>
    </div>
  );
}
