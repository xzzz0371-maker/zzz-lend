import { ADDRESSES, ETHERSCAN_URL } from "@/lib/config";

const CONTRACTS = [
  { name: "LendingPool", addr: ADDRESSES.lendingPool },
  { name: "MockUSDC", addr: ADDRESSES.usdc },
  { name: "SwitchableOracle", addr: ADDRESSES.switchableOracle },
  { name: "ChainlinkOracle", addr: ADDRESSES.chainlinkOracle },
  { name: "InterestRateModel", addr: ADDRESSES.interestRateModel },
  { name: "RiskManager", addr: ADDRESSES.riskManager },
  { name: "LiquidationManager", addr: ADDRESSES.liquidationManager },
  { name: "ReserveManager", addr: ADDRESSES.reserveManager },
  { name: "RiskEngine", addr: ADDRESSES.riskEngine },
];

export default function AboutPage() {
  return (
    <div className="mx-auto max-w-3xl space-y-8">
      <section>
        <h1 className="text-2xl font-bold text-white">About ZZZ Lend</h1>
        <p className="mt-3 text-sm leading-relaxed text-slate-500">
          ZZZ Lend is a risk-layered DeFi lending protocol. Depositors supply USDC and earn dynamic
          estimated yield; borrowers collateralize ETH and choose one of five LTV risk tiers
          (50–80%). The system prices risk in real time: higher tiers mean higher borrowing power,
          higher estimated yields — and higher risk.
        </p>
        <p className="mt-3 text-sm leading-relaxed text-slate-500">
          Bad debt beyond the risk reserve is shared by all depositors proportionally, similar to a
          fund whose NAV can decline. The risk reserve targets 3% of total borrows; excess reserve
          is automatically diverted to the treasury.
        </p>
      </section>

      <section className="card p-5">
        <h2 className="mb-3 text-lg font-semibold text-slate-800">Risk Disclosure</h2>
        <ul className="list-disc space-y-2 pl-5 text-sm text-slate-500">
          <li>
            <strong className="text-slate-200">Bad debt risk:</strong> deposits are not guaranteed.
            If bad debt exceeds the risk reserve, your principal may decrease.
          </li>
          <li>
            <strong className="text-slate-200">Oracle risk:</strong> prices come from Chainlink with
            staleness and deviation checks, but feeds can lag or be paused.
          </li>
          <li>
            <strong className="text-slate-200">Liquidation risk:</strong> if your Health Factor
            drops below 1, your collateral may be liquidated at a 5% bonus to liquidators.
          </li>
          <li>
            <strong className="text-slate-200">Liquidity risk:</strong> withdrawals may fail if pool
            liquidity is insufficient.
          </li>
          <li>
            <strong className="text-slate-200">Smart contract risk:</strong> unaudited by an
            independent third party; use at your own risk on testnet only.
          </li>
        </ul>
      </section>

      <section>
        <h2 className="mb-3 text-lg font-semibold text-slate-800">Deployed Contracts (Sepolia)</h2>
        <div className="card overflow-x-auto p-4">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="text-slate-500">
                <th className="px-2 py-2">Contract</th>
                <th className="px-2 py-2">Address</th>
              </tr>
            </thead>
            <tbody>
              {CONTRACTS.map((c) => (
                <tr key={c.name} className="border-t border-slate-200/70">
                  <td className="px-2 py-2 text-slate-300">{c.name}</td>
                  <td className="px-2 py-2">
                    <a
                      className="text-accent hover:underline"
                      href={`${ETHERSCAN_URL}/address/${c.addr}`}
                      target="_blank"
                      rel="noreferrer"
                    >
                      {c.addr.slice(0, 8)}…{c.addr.slice(-6)}
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      <section className="card p-5">
        <h2 className="mb-2 text-lg font-semibold text-slate-800">Audit Status</h2>
        <p className="text-sm text-slate-500">
          Security review completed, pending third-party audit.
        </p>
      </section>

      <section className="card border-danger/40 p-5">
        <h2 className="mb-2 text-lg font-semibold text-danger">Disclaimer</h2>
        <p className="text-sm text-slate-500">
          This is a testnet demo connected to Sepolia. It uses mock test assets and simulated
          history. Nothing on this page is an offer of financial products, and no returns are
          guaranteed. Do not use real funds.
        </p>
      </section>
    </div>
  );
}
