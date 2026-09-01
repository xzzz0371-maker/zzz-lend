"use client";

import { ResponsiveContainer, LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, Legend, ReferenceLine } from "recharts";

// Interest-rate curve for the NORMAL preset (base 0.5%, slope1 4%, kink 80%, slope2 50%).
// Estimated — matches the deployed InterestRateModel's NORMAL preset.
const TIER_PREMIUM: Record<number, number> = { 1: 0, 2: 1, 3: 2, 4: 3, 5: 4.5 };

function aprAt(util: number, tier: number): number {
  const base = 0.5;
  const slope1 = 4;
  const kink = 80;
  const slope2 = 50;
  let r = base;
  if (util <= kink) r += (slope1 * util) / 100;
  else r += (slope1 * kink) / 100 + (slope2 * (util - kink)) / 100;
  return r + TIER_PREMIUM[tier];
}

export function RateCurve({ height = 260 }: { height?: number }) {
  const data = Array.from({ length: 21 }, (_, i) => {
    const util = i * 5;
    return {
      util,
      "Tier 1": Number(aprAt(util, 1).toFixed(2)),
      "Tier 5": Number(aprAt(util, 5).toFixed(2)),
    };
  });

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 12, left: -12, bottom: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="rgba(15,23,42,0.08)" />
          <XAxis
            dataKey="util"
            tickFormatter={(v) => `${v}%`}
            tick={{ fill: "#64748b", fontSize: 11 }}
            axisLine={{ stroke: "rgba(15,23,42,0.12)" }}
            tickLine={false}
            label={{ value: "Utilization", position: "insideBottom", offset: -2, fill: "#64748b", fontSize: 11 }}
          />
          <YAxis
            tick={{ fill: "#64748b", fontSize: 11 }}
            tickFormatter={(v) => `${v}%`}
            axisLine={false}
            tickLine={false}
          />
          <Tooltip
            formatter={(v) => [`~${v}%`, undefined]}
            labelFormatter={(l) => `Utilization ${l}%`}
            contentStyle={{
              background: "rgba(255,255,255,0.92)",
              border: "1px solid rgba(15,23,42,0.1)",
              borderRadius: 12,
              boxShadow: "0 8px 24px rgba(15,23,42,0.12)",
              fontSize: 12,
            }}
          />
          <Legend wrapperStyle={{ fontSize: 12 }} />
          <ReferenceLine x={80} stroke="#f59e0b" strokeDasharray="4 4" label={{ value: "kink 80%", fill: "#f59e0b", fontSize: 10 }} />
          <Line type="monotone" dataKey="Tier 1" stroke="#3b82f6" strokeWidth={2} dot={false} />
          <Line type="monotone" dataKey="Tier 5" stroke="#f97316" strokeWidth={2} dot={false} />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
