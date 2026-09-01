"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectButton } from "./ConnectButton";

const links = [
  { href: "/", label: "Home" },
  { href: "/dashboard", label: "Dashboard" },
  { href: "/stress-test", label: "Stress Test" },
  { href: "/history", label: "History" },
  { href: "/about", label: "About" },
];

export function NavBar() {
  const pathname = usePathname();
  return (
    <header className="sticky top-0 z-30 border-b border-border bg-bg/80 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center justify-between gap-4 px-4 py-3">
        <Link href="/" className="flex items-center gap-2">
          <span className="flex h-7 w-7 items-center justify-center rounded-md bg-accent text-sm font-bold text-white">
            Z
          </span>
          <span className="text-base font-bold text-slate-100">ZZZ Lend</span>
        </Link>
        <nav className="hidden items-center gap-1 md:flex">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className={`rounded-lg px-3 py-1.5 text-sm ${
                pathname === l.href
                  ? "bg-border text-white"
                  : "text-slate-400 hover:text-white"
              }`}
            >
              {l.label}
            </Link>
          ))}
        </nav>
        <div className="flex items-center gap-3">
          <span className="hidden items-center gap-1.5 rounded-full bg-success/10 px-2 py-1 text-xs text-success sm:flex">
            <span className="h-1.5 w-1.5 rounded-full bg-success" />
            Sepolia Testnet
          </span>
          <ConnectButton />
        </div>
      </div>
      {/* mobile nav */}
      <nav className="flex items-center gap-1 overflow-x-auto px-4 pb-2 md:hidden">
        {links.map((l) => (
          <Link
            key={l.href}
            href={l.href}
            className={`whitespace-nowrap rounded-lg px-3 py-1.5 text-sm ${
              pathname === l.href ? "bg-border text-white" : "text-slate-400"
            }`}
          >
            {l.label}
          </Link>
        ))}
      </nav>
    </header>
  );
}
