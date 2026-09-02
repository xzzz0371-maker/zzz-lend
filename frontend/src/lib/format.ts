// Number / address formatting helpers (USDC 6-dec, ETH 18-dec, WAD 1e18).

const POW10 = (dec: number): bigint => 10n ** BigInt(dec);

export function rawToNum(raw: bigint | undefined | null, decimals = 6): number {
  if (raw === undefined || raw === null) return 0;
  return Number(raw) / Number(POW10(decimals));
}

export function numToRaw(n: number, decimals = 6): bigint {
  if (!isFinite(n) || n <= 0) return 0n;
  return BigInt(Math.floor(n * Number(POW10(decimals))));
}

export function formatToken(raw: bigint | number | undefined | null, decimals = 6, dec = 2): string {
  if (raw === undefined || raw === null) return "--";
  return formatAmount(Number(raw) / Number(POW10(decimals)), dec);
}

export function formatUsd(n: number, dec = 2): string {
  if (!isFinite(n)) return "--";
  return `$${n.toLocaleString("en-US", { minimumFractionDigits: dec, maximumFractionDigits: dec })}`;
}

export function formatUsdc(raw: bigint | number | undefined | null, decimals = 2): string {
  if (raw === undefined || raw === null) return "--";
  const n = Number(raw) / 1e6;
  return formatAmount(n, decimals);
}

export function formatEth(raw: bigint | number | undefined | null, decimals = 4): string {
  if (raw === undefined || raw === null) return "--";
  const n = Number(raw) / 1e18;
  return formatAmount(n, decimals);
}

export function formatWadPct(raw: bigint | number | undefined | null, decimals = 2): string {
  if (raw === undefined || raw === null) return "--";
  const n = (Number(raw) / 1e18) * 100;
  return `${formatAmount(n, decimals)}%`;
}

export function formatWad(raw: bigint | number | undefined | null, decimals = 2): string {
  if (raw === undefined || raw === null) return "--";
  return formatAmount(Number(raw) / 1e18, decimals);
}

export function formatAmount(n: number, decimals = 2): string {
  if (!isFinite(n)) return "--";
  return n.toLocaleString("en-US", {
    minimumFractionDigits: decimals,
    maximumFractionDigits: decimals,
  });
}

// Format an APY value (already in % per year) with a leading "~".
export function formatApy(pct: number | undefined | null, decimals = 2): string {
  if (pct === undefined || pct === null || !isFinite(pct)) return "~--%";
  return `~${formatAmount(pct, decimals)}%`;
}

export function truncateAddress(addr: string | undefined): string {
  if (!addr) return "";
  return `${addr.slice(0, 6)}...${addr.slice(-4)}`;
}

export function formatHealthFactor(hf: bigint | number | undefined | null): string {
  if (hf === undefined || hf === null) return "--";
  const n = Number(hf) / 1e18;
  return n === Number.MAX_SAFE_INTEGER ? "∞" : formatAmount(n, 2);
}

// Color-coded HF helper.
export function hfTone(hf: bigint | number | undefined | null): "success" | "warning" | "danger" {
  if (hf === undefined || hf === null) return "danger";
  const n = Number(hf) / 1e18;
  if (n >= 1.5) return "success";
  if (n >= 1) return "warning";
  return "danger";
}
