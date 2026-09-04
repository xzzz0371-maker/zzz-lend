"use client";

import { type Hash } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

export function TxStatus({ hash }: { hash?: Hash }) {
  const { data, isPending, isError } = useWaitForTransactionReceipt({ hash });
  if (!hash) return null;

  if (isPending) {
    return (
      <div className="flex items-center gap-2 text-xs text-amber-600">
        <svg className="h-3.5 w-3.5 animate-spin" viewBox="0 0 24 24" fill="none">
          <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
          <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v4a4 4 0 00-4 4H4z" />
        </svg>
        <span>Confirming… {hash.slice(0, 10)}</span>
      </div>
    );
  }
  if (isError) {
    return <p className="text-xs text-red-600">Transaction failed.</p>;
  }
  if (data?.status === "success") {
    return (
      <p className="text-xs text-emerald-600">
        ✓ Confirmed{" "}
        <a
          className="underline"
          href={`https://basescan.org/tx/${hash}`}
          target="_blank"
          rel="noreferrer"
        >
          {hash.slice(0, 10)}
        </a>
      </p>
    );
  }
  return <p className="text-xs text-red-600">Transaction reverted.</p>;
}
