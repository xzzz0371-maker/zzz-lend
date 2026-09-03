import "dotenv/config";
import fs from "node:fs";
import path from "node:path";
import type { Address } from "viem";

import { init, loadDeployments } from "./rpc.js";
import { checkPosition, snapshotMarket, utilization, reserveBalanceOf, assetPrice, describeHf, describeMarket } from "./checkers.js";
import { AlertStore } from "./alerts.js";
import { appendLine, touchFile, nowIso, WAD } from "./util.js";

interface PositionsCfg {
  markets: { id: number; symbol: string; token: Address; decimals: number }[];
  collaterals: { id: number; symbol: string; token: Address; decimals: number }[];
  users: Address[];
}

function envOr(name: string, dflt: string): string {
  return process.env[name] ?? dflt;
}

function loadCfg(): PositionsCfg {
  const p = path.resolve(process.cwd(), "config", "positions.json");
  return JSON.parse(fs.readFileSync(p, "utf8")) as PositionsCfg;
}

async function main() {
  const rpcUrl = envOr("RPC_URL", "");
  if (!rpcUrl) {
    console.error("RPC_URL missing");
    process.exit(1);
  }
  const deploymentsPath = path.resolve(
    envOr("DEPLOYMENTS", "../frontend/src/lib/deployments/sepolia.json")
  );
  const outDir = path.resolve(envOr("OUT_DIR", "./out"));
  touchFile(path.join(outDir, ".keep"));

  init({ rpcUrl, deploymentsJson: deploymentsPath });
  const d = loadDeployments(deploymentsPath);
  const pool = d.lendingPool;
  const rm = d.reserveManager;
  const oracle = d.oracle;
  const cfg = loadCfg();
  const pollSec = parseInt(envOr("POLL_SECONDS", "60"), 10);
  const loop = process.argv.includes("--loop");

  const alertsFile = path.join(outDir, "alerts.log");
  const metricsFile = path.join(outDir, "metrics.jsonl");
  const alerts = new AlertStore((a) => {
    const line = `[${a.at}] [${a.level}] ${a.message}`;
    console.log(line);
    appendLine(alertsFile, a);
  });

  console.log(`monitor: pool=${pool} rm=${rm} oracle=${oracle} loop=${loop} interval=${pollSec}s`);

  async function tick() {
    const ts = nowIso();
    const row: Record<string, unknown> = { ts };

    // ---- markets ----
    for (const m of cfg.markets) {
      const snap = await snapshotMarket(pool, m.id);
      if (!snap) {
        alerts.set(`mkt-${m.id}-read`, "WARN", true, `market ${m.id} read failed (maybe no such market)`);
        continue;
      }
      alerts.set(`mkt-${m.id}-read`, "WARN", false, "");
      row[`m${m.id}.market`] = describeMarket(snap);
      const u = utilization(snap);
      row[`m${m.id}.utilization`] = u.toString();
      if (u > 95n * WAD / 100n) {
        alerts.set(`mkt-${m.id}-util`, "WARN", true, `m${m.id} utilization high ${describeMarket(snap)}`);
      } else {
        alerts.set(`mkt-${m.id}-util`, "WARN", false, "");
      }
      // 储备覆盖率 = reserveManager.balanceOf / totalBorrows
      const rsv = await reserveBalanceOf(rm, m.token);
      if (rsv !== null) {
        row[`m${m.id}.reserveBal`] = rsv.toString();
        if (snap.borrows > 0n) {
          const cov = (rsv * WAD) / snap.borrows;
          row[`m${m.id}.reserveCovPct`] = cov.toString();
          if (cov < (3n * WAD) / 100n) {
            alerts.set(`mkt-${m.id}-reserve`, "WARN", true, `m${m.id} reserve coverage low: ${describeMarket(snap)}`);
          } else {
            alerts.set(`mkt-${m.id}-reserve`, "WARN", false, "");
          }
        }
      }
    }

    // ---- positions / liquidatable watch ----
    for (const user of cfg.users) {
      const p = await checkPosition(pool, user);
      if (!p) continue;
      row[`user.${user}.hf`] = describeHf(p.hf);
      row[`user.${user}.liquidatable`] = p.liquidatable;
      if (p.liquidatable) {
        alerts.set(`liq-${user}`, "CRITICAL", true, `user ${user} liquidatable (hf=${describeHf(p.hf)})`);
      } else {
        alerts.set(`liq-${user}`, "CRITICAL", false, "");
      }
      if (!p.liquidatable && p.hf < 11n * WAD / 10n && p.hf > 0n) {
        alerts.set(`hf-${user}`, "WARN", true, `user ${user} HF low ${describeHf(p.hf)}`);
      } else {
        alerts.set(`hf-${user}`, "WARN", false, "");
      }
    }

    // ---- oracle sanity ----
    for (const c of cfg.collaterals) {
      const px = await assetPrice(oracle, c.token);
      row[`oracle.${c.symbol}`] = px === null ? "stale/unavailable" : px.toString();
      if (px === null || px === 0n) {
        alerts.set(`oracle-${c.symbol}`, "CRITICAL", true, `oracle price for ${c.symbol} unavailable/stale`);
      } else {
        alerts.set(`oracle-${c.symbol}`, "CRITICAL", false, "");
      }
    }

    appendLine(metricsFile, row);
  }

  await tick();
  if (loop) {
    setInterval(tick, pollSec * 1000);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
