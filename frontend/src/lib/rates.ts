// NORMAL preset interest-rate model (estimated; matches contracts InterestRateModel NORMAL, three-segment).
const BASE = 0.5;
const SLOPE1 = 4; // 0..KINK1
const KINK1 = 80;
const SLOPE2A = 25; // KINK1..KINK2
const KINK2 = 85;
const SLOPE2 = 50; // > KINK2
const PREMIUM: Record<number, number> = { 1: 0, 2: 1, 3: 2, 4: 3, 5: 4.5 };

export function borrowAprAt(utilPct: number, tier: number): number {
  let r = BASE;
  if (utilPct <= KINK1) r += (SLOPE1 * utilPct) / 100;
  else if (utilPct <= KINK2)
    r += (SLOPE1 * KINK1) / 100 + (SLOPE2A * (utilPct - KINK1)) / 100;
  else
    r +=
      (SLOPE1 * KINK1) / 100 +
      (SLOPE2A * (KINK2 - KINK1)) / 100 +
      (SLOPE2 * (utilPct - KINK2)) / 100;
  return r + (PREMIUM[tier] ?? 0);
}

export function supplyAprAt(utilPct: number, avgBorrowRatePct: number): number {
  return avgBorrowRatePct * (utilPct / 100) * 0.94; // 94% depositor share
}

// Projected supply APY: assumes a fixed utilization (80%) and 94% depositor share.
export const PROJECTED_UTIL_PCT = 80;
export function projectedSupplyApyPct(): number {
  const r = borrowAprAt(PROJECTED_UTIL_PCT, 1); // tier-1 borrow rate at 80% utilization
  return r * (PROJECTED_UTIL_PCT / 100) * 0.94;
}

// Upper bound for borrow APR display at a defined high utilization.
export function borrowAprUpperPct(tier: number, highUtilPct = 90): number {
  return borrowAprAt(highUtilPct, tier);
}
