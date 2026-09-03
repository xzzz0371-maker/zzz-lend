import type { Address } from "viem";
import { abiFor, tryRead } from "./rpc.js";
import { WAD, hfPct, fmtPct } from "./util.js";

export interface PositionCheck {
  user: Address;
  liquidatable: boolean;
  hf: bigint;
  debtWad: bigint;
  collWad: bigint;
}

export interface MarketSnap {
  marketId: number;
  cash: bigint;
  borrows: bigint;
  supply: bigint;
  reserve: bigint;
  treasury: bigint;
  supplyIdx: bigint;
}

export async function checkPosition(pool: Address, user: Address): Promise<PositionCheck | null> {
  const pos = await tryRead(pool, abiFor("LendingPool"), "getUserPositionV2", [user]);
  if (!pos) return null;
  const [debtWad, collWad, hf, liquidatable] = pos as [bigint, bigint, bigint, boolean];
  return { user, liquidatable, hf, debtWad, collWad };
}

export async function snapshotMarket(pool: Address, marketId: number): Promise<MarketSnap | null> {
  const acct = (await tryRead(pool, abiFor("LendingPool"), "marketAccounts", [marketId])) as
    | [bigint, bigint, bigint, bigint, bigint, bigint]
    | null;
  if (!acct) return null;
  const [cash, borrows, supply, reserve, treasury, supplyIdx] = acct;
  return { marketId, cash, borrows, supply, reserve, treasury, supplyIdx };
}

export function utilization(s: MarketSnap): bigint {
  const total = s.cash + s.borrows;
  return total === 0n ? 0n : (s.borrows * WAD) / total;
}

export function describeHf(hf: bigint): string {
  return hf >= 2n ** 255n ? "inf" : hfPct(hf);
}

export function describeMarket(s: MarketSnap): string {
  return `m${s.marketId} util=${fmtPct(utilization(s))} cash=${s.cash} borrows=${s.borrows} reserve=${s.reserve} treasury=${s.treasury}`;
}

/** 储备余额（ReserveManager 每 token 独立）。 */
export async function reserveBalanceOf(rm: Address, token: Address): Promise<bigint | null> {
  const v = await tryRead(rm, abiFor("ReserveManager"), "balanceOf", [token]);
  return v === null ? null : (v as bigint);
}

/** 喂价（ChainlinkOracle.getAssetPrice）；stale/异常会 revert → null。 */
export async function assetPrice(oracle: Address, token: Address): Promise<bigint | null> {
  const v = await tryRead(oracle, abiFor("ChainlinkOracle"), "getAssetPrice", [token]);
  return v === null ? null : (v as bigint);
}
