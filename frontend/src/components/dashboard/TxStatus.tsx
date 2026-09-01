"use client";

import { type Hash } from "viem";
import { useWaitForTransactionReceipt } from "wagmi";

export function TxStatus({ hash }: { hash?: Hash }) {
  const { data, isPending, isError } = useWaitForTransactionReceipt({ hash });
  if (!hash) return null;
  if (isPending) {
    return <p className="text-xs text-warning">Transaction pending… {hash.slice(0, 10)}</p>;
  }
  if (isError) {
    return <p className="text-xs text-danger">Transaction failed.</p>;
  }
  if (data?.status === "success") {
    return <p className="text-xs text-success">Confirmed ✓ {hash.slice(0, 10)}</p>;
  }
  return <p className="text-xs text-danger">Transaction reverted.</p>;
}
