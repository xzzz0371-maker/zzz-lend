import "dotenv/config";
import { createPublicClient, http, type Address } from "viem";
import { base } from "viem/chains";
import { FEEDS } from "../feeds.js";

const RPC = process.env.BASE_RPC_URL ?? "https://mainnet.base.org";
const STALE_MULT = Number(process.env.STALE_MULT ?? 3); // 允许 heartbeat 的倍数作为 stale 容忍（stable 偏差 feed 常低于 heartbeat 更新）
const client = createPublicClient({ chain: base, transport: http(RPC) });

const ABI = [
  {
    type: "function",
    name: "description",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "string" }],
  },
  {
    type: "function",
    name: "decimals",
    stateMutability: "view",
    inputs: [],
    outputs: [{ type: "uint8" }],
  },
  {
    type: "function",
    name: "latestRoundData",
    stateMutability: "view",
    inputs: [],
    outputs: [
      { type: "uint80" },
      { type: "int256" },
      { type: "uint256" },
      { type: "uint256" },
      { type: "uint80" },
    ],
  },
] as const;

async function checkFeed(feed: (typeof FEEDS)[number]) {
  const p = feed.proxy as Address;
  const out: Record<string, unknown> = { symbol: feed.symbol, proxy: p };
  let ok = true;
  try {
    const [description, decimals, round] = await client.multicall({
      contracts: [
        { address: p, abi: ABI, functionName: "description" },
        { address: p, abi: ABI, functionName: "decimals" },
        { address: p, abi: ABI, functionName: "latestRoundData" },
      ],
    });
    const desc = description.result as unknown as string;
    const dec = Number(decimals.result as unknown as bigint);
    if (round.status !== "success") throw new Error("latestRoundData failed");
    const [, answerRaw, , updatedAtRaw] = round.result as [bigint, bigint, bigint, bigint, bigint];
    const answer = answerRaw as bigint;
    const updatedAt = Number(updatedAtRaw as unknown as bigint);
    const now = Math.floor(Date.now() / 1000);
    const age = now - updatedAt;
    out.desc = desc;
    out.decimals = dec;
    out.price = (Number(answer) / 10 ** dec).toFixed(8);
    out.updatedAt = new Date(updatedAt * 1000).toISOString();
    out.ageSec = age;

    const tol = feed.heartbeatSec * STALE_MULT;
    if (desc.trim() !== feed.description.trim()) { out.error = `description mismatch: got '${desc}'`; ok = false; }
    if (dec !== feed.decimals) { out.error = `decimals mismatch: ${dec} != ${feed.decimals}`; ok = false; }
    if (answer <= 0n) { out.error = "answer <= 0"; ok = false; }
    if (age > tol) { out.error = `stale: age ${age}s > heartbeat*${STALE_MULT}(${tol}s)`; ok = false; }
    out.heartbeatSec = feed.heartbeatSec;
    out.tolSec = tol;
  } catch (e) {
    ok = false;
    out.error = (e as Error).message;
  }
  out.status = ok ? "OK" : "STALE/FAIL";
  return out;
}

async function main() {
  console.log(`feed health check · chain=Base(8453) · rpc=${RPC} · staleTol=heartbeat*${STALE_MULT}`);
  const results = [];
  for (const f of FEEDS) results.push(await checkFeed(f));
  const table = results.map((r) => {
    return `| ${r.symbol} | ${r.proxy} | ${r.desc ?? "-"} | ${r.decimals ?? "-"} | ${r.price ?? "-"} | ${r.ageSec ?? "-"}s | ${r.heartbeatSec ?? "-"}s | ${r.status} | ${r.error ?? ""} |`;
  });
  console.log("| symbol | proxy | description | decimals | price | age | heartbeat | status | error |");
  console.log("|---|---|---|---|---|---|---|---|---|");
  table.forEach((t) => console.log(t));
  const fails = results.filter((r) => r.status !== "OK").length;
  console.log(`\nresult: ${results.length - fails}/${results.length} OK`);
  if (fails > 0) process.exitCode = 1;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
