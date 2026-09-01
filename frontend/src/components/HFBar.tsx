"use client";

// Health Factor progress bar. HF < 1 = liquidation zone, 1-1.5 = warning, > 1.5 = safe.
export function HFBar({ hf }: { hf: number }) {
  const max = 3;
  const clamped = Math.min(max, Math.max(0, hf));
  const pct = (clamped / max) * 100;

  const tone =
    hf >= 1.5
      ? "text-emerald-600"
      : hf >= 1
        ? "text-amber-600"
        : "text-red-600";

  return (
    <div>
      <div className="relative h-2.5 w-full overflow-hidden rounded-full bg-slate-200/70">
        <div
          className="h-full rounded-full"
          style={{
            width: `${pct}%`,
            background: "linear-gradient(90deg, #ef4444 0%, #f59e0b 55%, #10b981 100%)",
            transition: "width 0.6s ease",
          }}
        />
        {/* markers */}
        <div className="absolute inset-y-0 left-1/3 w-px bg-white/70" title="HF 1.0" />
        <div className="absolute inset-y-0 left-1/2 w-px bg-white/70" title="HF 1.5" />
      </div>
      <div className="mt-1 flex justify-between text-[10px] text-slate-500">
        <span>0</span>
        <span>1.0 liq</span>
        <span>1.5</span>
        <span>3+</span>
      </div>
      <div className={`mt-1 text-right text-sm font-bold ${tone}`}>
        Health Factor {hf === Number.MAX_SAFE_INTEGER ? "∞" : hf.toFixed(2)}
      </div>
    </div>
  );
}
