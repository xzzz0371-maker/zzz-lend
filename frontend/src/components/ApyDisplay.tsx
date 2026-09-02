"use client";

import { CountUp } from "./CountUp";
import { projectedSupplyApyPct, PROJECTED_UTIL_PCT } from "@/lib/rates";

// Supply APY display: shows the projected APY when the pool is empty (avoids a bare 0%),
// and the current real APY when utilization > 0. Projected values always note the assumption.
export function SupplyApyDisplay({ currentPct, utilPct }: { currentPct: number; utilPct: number }) {
  const projected = projectedSupplyApyPct();
  const isEmpty = utilPct <= 0.0001;
  const main = isEmpty ? projected : currentPct;

  return (
    <div>
      <div className="text-2xl font-bold text-emerald-600">
        ~<CountUp value={main} decimals={2} suffix="%" />
        {!isEmpty && <span className="ml-1 text-xs font-medium text-slate-400">(Current)</span>}
      </div>
      <div className="mt-0.5 text-xs text-slate-500">
        {isEmpty ? (
          <>
            Current: ~0% — no active borrows. Projected assumes {PROJECTED_UTIL_PCT}% utilization.
          </>
        ) : (
          <>
            Projected: ~{projected.toFixed(2)}% (assumes {PROJECTED_UTIL_PCT}% utilization)
          </>
        )}
      </div>
    </div>
  );
}
