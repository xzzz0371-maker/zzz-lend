"use client";

// Custom stacked-bar yield breakdown (Gross / Expected Loss / Fee / Reserve / Net).
export function YieldBreakdown({ gross }: { gross: number }) {
  const loss = gross * 0.12;
  const fee = gross * 0.03;
  const reserve = gross * 0.05;
  const net = Math.max(0, gross - loss - fee - reserve);
  const total = Math.max(gross, 1);

  const rows = [
    { label: "Gross Yield", value: gross, color: "#3b82f6", positive: true },
    { label: "Expected Loss", value: loss, color: "#ef4444", positive: false },
    { label: "Protocol Fee", value: fee, color: "#f59e0b", positive: false },
    { label: "Reserve", value: reserve, color: "#8b5cf6", positive: false },
    { label: "Estimated Net APY", value: net, color: "#10b981", positive: true },
  ];

  return (
    <div className="space-y-2">
      {rows.map((r) => (
        <div key={r.label}>
          <div className="flex justify-between text-xs">
            <span className="text-slate-500">{r.label}</span>
            <span className={r.positive ? "font-semibold text-emerald-600" : "text-slate-600"}>
              ~{r.value.toFixed(2)}%
            </span>
          </div>
          <div className="mt-0.5 h-2 overflow-hidden rounded-full bg-slate-200/70">
            <div
              className="h-full rounded-full"
              style={{
                width: `${Math.min(100, (r.value / total) * 100)}%`,
                background: r.color,
              }}
            />
          </div>
        </div>
      ))}
      <p className="pt-1 text-[11px] text-slate-500">Estimates only — not a guarantee of return.</p>
    </div>
  );
}
