"use client";

import { useState } from "react";
import { useAccount, useChainId, useConnect, useDisconnect } from "wagmi";
import { truncateAddress } from "@/lib/format";

export function ConnectButton() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { connectors, connectAsync, reset } = useConnect();
  const { disconnect } = useDisconnect();

  const [open, setOpen] = useState(false);
  const [connectingId, setConnectingId] = useState<string | null>(null);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);

  const hasWallet =
    typeof window !== "undefined" && !!(window as unknown as { ethereum?: unknown }).ethereum;

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async function handleConnect(connector: any) {
    setErrorMsg(null);
    setConnectingId(connector.id);
    try {
      await connectAsync({ connector });
      setOpen(false);
    } catch (e) {
      const err = e as { shortMessage?: string; message?: string };
      setErrorMsg(
        err?.shortMessage ??
          err?.message ??
          "Connection failed — make sure your wallet is unlocked.",
      );
    } finally {
      setConnectingId(null);
      reset();
    }
  }

  if (isConnected && address) {
    return (
      <div className="flex items-center gap-2">
        {chainId !== 11155111 && (
          <span className="rounded-full bg-danger/20 px-2 py-1 text-xs text-danger">
            Wrong network — switch to Sepolia
          </span>
        )}
        <button onClick={() => setOpen((v) => !v)} className="btn-outline">
          {truncateAddress(address)}
        </button>
        {open && (
          <button
            onClick={() => {
              disconnect();
              setOpen(false);
            }}
            className="btn-outline text-danger"
          >
            Disconnect
          </button>
        )}
      </div>
    );
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="btn-primary"
        type="button"
      >
        Connect Wallet
      </button>

      {open && (
        <div className="card absolute right-0 z-20 mt-2 w-64 p-2">
          {!hasWallet ? (
            <div className="space-y-2 p-2 text-center">
              <p className="text-sm text-warning">No wallet detected</p>
              <p className="text-xs text-slate-400">
                Install the MetaMask browser extension (or another injected wallet), then refresh
                this page and connect again.
              </p>
            </div>
          ) : (
            <div className="space-y-1">
              <p className="px-2 pt-1 text-xs text-slate-500">Select a wallet to connect:</p>
              {connectors.map((c) => (
                <button
                  key={c.id}
                  className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-left text-sm text-slate-200 hover:bg-border disabled:opacity-50"
                  disabled={connectingId !== null}
                  onClick={() => handleConnect(c)}
                  type="button"
                >
                  <span className="h-2 w-2 rounded-full bg-accent" />
                  <span className="flex-1">{c.name}</span>
                  {connectingId === c.id && <span className="text-xs text-slate-400">connecting…</span>}
                </button>
              ))}
              {errorMsg && <p className="px-2 pb-1 pt-1 text-xs text-danger">{errorMsg}</p>}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
