"use client";

import { useState } from "react";
import { type Address } from "viem";
import { useAccount, useBalance, useWriteContract } from "wagmi";
import { LendingPoolAbi, MockTokenAbi } from "@/lib/abis";
import { ADDRESSES, COLLATERALS, MIN_COLLATERAL_TOKENS, ETH, type CollateralInfo } from "@/lib/config";
import { useUserPositionV2, useTokenBalance, useTokenAllowance } from "@/lib/hooks";
import { formatToken, formatUsd, numToRaw, rawToNum } from "@/lib/format";
import { TxStatus } from "./TxStatus";

function CollateralRow({
  coll,
  deposited,
  priceUsd,
}: {
  coll: CollateralInfo;
  deposited: bigint;
  priceUsd: number;
}) {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const amountNum = parseFloat(amount);
  const raw = numToRaw(amountNum, coll.decimals);

  const ercBalance = useTokenBalance(
    coll.native ? undefined : (coll.address as Address),
    address as Address,
  );
  const nativeBalance = useBalance({ address: address as Address });
  const balance = coll.native ? (nativeBalance.data?.value ?? 0n) : ercBalance;
  const { allowance, refetch: refetchAllowance } = useTokenAllowance(
    coll.native ? undefined : (coll.address as Address),
    address as Address,
    ADDRESSES.lendingPool as Address,
  );
  const needApproval = !coll.native && raw > 0n && allowance < raw;

  const { data: hash, isPending, writeContract } = useWriteContract();

  const minRaw = numToRaw(MIN_COLLATERAL_TOKENS, coll.decimals);
  const depositValid = amountNum >= MIN_COLLATERAL_TOKENS && raw > 0n && raw <= balance;
  const withdrawValid = raw > 0n && raw <= deposited;

  const valueUsd = rawToNum(deposited, coll.decimals) * priceUsd;

  return (
    <div className="rounded-xl bg-white/60 p-3 ring-1 ring-slate-200/60">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="font-semibold text-slate-800">{coll.symbol}</span>
          <span className="text-xs text-slate-400">{coll.name}</span>
        </div>
        <span className="text-xs text-slate-500">
          Deposited {formatToken(deposited, coll.decimals, 4)} · {formatUsd(valueUsd)}
        </span>
      </div>
      <div className="mt-2 flex gap-2">
        <input
          type="number"
          className="input flex-1"
          placeholder="0.00"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
        />
        <button className="btn-outline whitespace-nowrap" onClick={() => setAmount(rawToNum(balance, coll.decimals).toString())}>
          Max
        </button>
      </div>
      <p className="mt-1 text-xs text-slate-500">
        Min {MIN_COLLATERAL_TOKENS} {coll.symbol} · Wallet: {formatToken(balance, coll.decimals, 4)}{" "}
        {coll.symbol}
      </p>
      <div className="mt-2 flex gap-2">
        {needApproval ? (
          <button
            className="btn-primary flex-1 text-xs"
            disabled={!address || !depositValid || isPending}
            onClick={() =>
              writeContract({
                address: coll.address as Address,
                abi: MockTokenAbi,
                functionName: "approve",
                args: [ADDRESSES.lendingPool as Address, raw],
              })
            }
          >
            {isPending ? "Approving…" : `Approve ${coll.symbol}`}
          </button>
        ) : (
          <button
            className="btn-primary flex-1 text-xs"
            disabled={!address || !depositValid || isPending}
            onClick={() =>
              coll.native
                ? writeContract({
                    address: ADDRESSES.lendingPool as Address,
                    abi: LendingPoolAbi,
                    functionName: "supplyCollateral",
                    args: [],
                    value: raw,
                  })
                : writeContract({
                    address: ADDRESSES.lendingPool as Address,
                    abi: LendingPoolAbi,
                    functionName: "supplyCollateral",
                    args: [coll.address as Address, raw],
                  })
            }
          >
            {isPending ? "Depositing…" : `Deposit ${coll.symbol}`}
          </button>
        )}
        <button
          className="btn-outline flex-1 text-xs"
          disabled={!address || !withdrawValid || isPending}
          onClick={() =>
            coll.native
              ? writeContract({
                  address: ADDRESSES.lendingPool as Address,
                  abi: LendingPoolAbi,
                  functionName: "withdrawCollateral",
                  args: [raw],
                })
              : writeContract({
                  address: ADDRESSES.lendingPool as Address,
                  abi: LendingPoolAbi,
                  functionName: "withdrawCollateral",
                  args: [coll.address as Address, raw],
                })
          }
        >
          {isPending ? "Withdrawing…" : `Withdraw ${coll.symbol}`}
        </button>
      </div>
      <TxStatus hash={hash} />
      {!coll.native && (
        <button className="mt-1 text-[11px] text-accent hover:underline" onClick={() => refetchAllowance()}>
          Refresh allowance
        </button>
      )}
      <p className="mt-1 text-[11px] text-slate-400">
        Withdrawing collateral below a healthy level is blocked by the protocol.
      </p>
    </div>
  );
}

export function CollateralTab({ prices }: { prices: Record<string, number> }) {
  const { address } = useAccount();
  const { position } = useUserPositionV2(address as Address);
  void ETH;
  return (
    <div className="space-y-3">
      <div className="rounded-lg bg-sky-50 px-3 py-2 text-xs text-sky-700 ring-1 ring-sky-200">
        Deposit ETH, wstETH or WBTC as collateral. Collateral is shared across all borrow markets
        (USDC / USDT / DAI). LTV &amp; liquidation thresholds are calibrated per asset.
      </div>
      {COLLATERALS.map((c) => (
        <CollateralRow
          key={c.id}
          coll={c}
          deposited={position?.collateral[c.id] ?? 0n}
          priceUsd={prices[c.address] ?? 0}
        />
      ))}
    </div>
  );
}
