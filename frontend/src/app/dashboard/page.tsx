"use client";

import { useSearchParams } from "next/navigation";
import { Suspense, useState } from "react";
import { type Address } from "viem";
import { useAccount, useWriteContract } from "wagmi";
import { MockUSDCAbi } from "@/lib/abis";
import { ADDRESSES } from "@/lib/config";
import { useUserPosition } from "@/lib/hooks";
import { PositionPanel } from "@/components/dashboard/PositionPanel";
import { SupplyTab } from "@/components/dashboard/SupplyTab";
import { WithdrawTab } from "@/components/dashboard/WithdrawTab";
import { BorrowTab } from "@/components/dashboard/BorrowTab";
import { RepayTab } from "@/components/dashboard/RepayTab";
import { TxStatus } from "@/components/dashboard/TxStatus";

const TABS = ["Supply", "Withdraw", "Borrow", "Repay"] as const;

export default function DashboardPage() {
  return (
    <Suspense fallback={<div className="card p-6 text-sm text-slate-500">Loading…</div>}>
      <DashboardInner />
    </Suspense>
  );
}

function DashboardInner() {
  const { address, isConnected } = useAccount();
  const params = useSearchParams();
  const initialTier = Math.min(Math.max(Number(params.get("tier") ?? 1), 1), 5);
  const [tab, setTab] = useState<number>(params.get("tab") === "borrow" ? 2 : 0);
  const { position } = useUserPosition(address as Address);
  const { data: faucetHash, isPending: faucetPending, writeContract: faucet } = useWriteContract();

  if (!isConnected) {
    return (
      <div className="card mx-auto max-w-md p-10 text-center">
        <h1 className="font-display text-2xl font-bold text-slate-800">Connect your wallet</h1>
        <p className="mt-2 text-sm text-slate-500">
          Connect to the Sepolia testnet to supply, borrow, withdraw and repay.
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h1 className="font-display text-2xl font-bold text-slate-900">Dashboard</h1>
        <button
          className="btn-outline text-xs"
          disabled={faucetPending}
          onClick={() =>
            faucet({
              address: ADDRESSES.usdc as Address,
              abi: MockUSDCAbi,
              functionName: "faucet",
              args: [BigInt(10_000e6)],
            })
          }
        >
          {faucetPending ? "Minting…" : "Get Test USDC (faucet 10,000)"}
        </button>
      </div>
      <TxStatus hash={faucetHash} />

      <div className="grid gap-6 lg:grid-cols-5">
        <div className="lg:col-span-2">
          <PositionPanel position={position} />
        </div>
        <div className="lg:col-span-3">
          <div className="card p-6">
            {/* segmented tabs */}
            <div className="mb-5 flex rounded-xl bg-slate-200/50 p-1">
              {TABS.map((t, i) => (
                <button
                  key={t}
                  onClick={() => setTab(i)}
                  className={`flex-1 rounded-lg px-4 py-2 text-sm font-semibold transition-all ${
                    tab === i
                      ? "bg-white text-accent shadow-sm"
                      : "text-slate-500 hover:text-slate-800"
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
            {tab === 0 && <SupplyTab />}
            {tab === 1 && <WithdrawTab />}
            {tab === 2 && <BorrowTab initialTier={initialTier} />}
            {tab === 3 && <RepayTab />}
          </div>
        </div>
      </div>
    </div>
  );
}
