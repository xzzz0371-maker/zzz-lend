import LendingPoolAbiRaw from "./abis/LendingPool.json";
import MockUSDCAbiRaw from "./abis/MockUSDC.json";
import SwitchableOracleAbiRaw from "./abis/SwitchableOracle.json";
import ChainlinkOracleAbiRaw from "./abis/ChainlinkOracle.json";
import RiskManagerAbiRaw from "./abis/RiskManager.json";

// Cast to `any` — the raw JSON ABI literal is too complex for wagmi's generic inference
// in a browser bundle, and we only need loosely-typed reads/writes in the demo frontend.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const LendingPoolAbi = LendingPoolAbiRaw as any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const MockUSDCAbi = MockUSDCAbiRaw as any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const SwitchableOracleAbi = SwitchableOracleAbiRaw as any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const ChainlinkOracleAbi = ChainlinkOracleAbiRaw as any;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export const RiskManagerAbi = RiskManagerAbiRaw as any;
