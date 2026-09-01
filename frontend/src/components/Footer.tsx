import { ADDRESSES, ETHERSCAN_URL } from "@/lib/config";

export function Footer() {
  return (
    <footer className="mt-12 border-t border-slate-200/60 bg-white/40 backdrop-blur-xl">
      <div className="mx-auto grid max-w-6xl gap-8 px-4 py-10 md:grid-cols-3">
        <div>
          <div className="flex items-center gap-2">
            <span className="flex h-6 w-6 items-center justify-center rounded-md bg-gradient-to-br from-accent to-blue-600 text-xs font-bold text-white">
              Z
            </span>
            <span className="font-display text-sm font-bold text-slate-800">ZZZ Lend</span>
          </div>
          <p className="mt-3 text-xs leading-relaxed text-slate-500">
            Risk-layered DeFi lending on Sepolia. Deposits are not guaranteed — your principal may
            decrease due to bad debt, like a fund whose NAV can decline.
          </p>
        </div>
        <div>
          <h4 className="text-xs font-bold uppercase tracking-wide text-slate-500">Protocol</h4>
          <ul className="mt-3 space-y-2 text-sm text-slate-600">
            <li>
              <a className="hover:text-accent" href={`${ETHERSCAN_URL}/address/${ADDRESSES.lendingPool}`} target="_blank" rel="noreferrer">
                LendingPool
              </a>
            </li>
            <li>
              <a className="hover:text-accent" href={`${ETHERSCAN_URL}/address/${ADDRESSES.usdc}`} target="_blank" rel="noreferrer">
                MockUSDC
              </a>
            </li>
            <li>
              <a className="hover:text-accent" href={`${ETHERSCAN_URL}/address/${ADDRESSES.switchableOracle}`} target="_blank" rel="noreferrer">
                Oracle
              </a>
            </li>
          </ul>
        </div>
        <div>
          <h4 className="text-xs font-bold uppercase tracking-wide text-slate-500">Status</h4>
          <ul className="mt-3 space-y-2 text-sm text-slate-600">
            <li>Chain: Sepolia (testnet)</li>
            <li>Version: 1.2.0</li>
            <li>Audit: Security review completed, pending third-party audit</li>
          </ul>
          <p className="mt-4 text-xs text-slate-500">
            All APY figures are estimates. No returns are guaranteed.
          </p>
        </div>
      </div>
    </footer>
  );
}
