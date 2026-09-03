// ZZZ Lend monitor — minimal helpers
import { existsSync, mkdirSync } from "node:fs";
import { writeFileSync, appendFileSync } from "node:fs";

export const WAD = 1_000_000_000_000_000_000n;

export function ensureDir(dir: string): void {
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function fmtPct(v: bigint): string {
  return `${(Number(v * 10000n / WAD) / 100).toFixed(2)}%`;
}

export function hfPct(v: bigint): string {
  if (v === 0n) return "0";
  if (v >= 2n ** 255n) return "inf";
  return (Number(v) / Number(WAD)).toFixed(3);
}

/** Append one JSON line to a file. */
export function appendLine(file: string, line: unknown): void {
  ensureDir(file.substring(0, file.lastIndexOf("/")));
  appendFileSync(file, JSON.stringify(line) + "\n", "utf8");
}

export function touchFile(file: string): void {
  ensureDir(file.substring(0, file.lastIndexOf("/")));
  writeFileSync(file, "", "utf8");
}
