import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/providers";
import { NavBar } from "@/components/NavBar";

export const metadata: Metadata = {
  title: "ZZZ Lend — Risk-Layered DeFi Lending",
  description:
    "Choose your risk tier, borrow against ETH, and earn on USDC. Estimated yields, no fixed income promises.",
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <Providers>
          <NavBar />
          <main className="mx-auto min-h-[80vh] max-w-6xl px-4 py-6">{children}</main>
          <footer className="border-t border-border py-6">
            <div className="mx-auto max-w-6xl px-4 text-center text-xs text-slate-500">
              ZZZ Lend is a testnet demo. Deposits are not guaranteed — your principal may
              decrease due to bad debt. All APY figures are estimates.
            </div>
          </footer>
        </Providers>
      </body>
    </html>
  );
}
