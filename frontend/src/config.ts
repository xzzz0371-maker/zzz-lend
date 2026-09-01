import { createConfig, http } from "wagmi";
import { type CreateConnectorFn } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { sepolia } from "./lib/chain";
import { RPC_URL, WC_PROJECT_ID } from "./lib/config";

// WalletConnect requires a project id. Without NEXT_PUBLIC_WC_PROJECT_ID only the
// injected connector (MetaMask / browser wallet) is enabled.
const connectors: CreateConnectorFn[] = [injected({ shimDisconnect: true })];
if (WC_PROJECT_ID) {
  connectors.push(walletConnect({ projectId: WC_PROJECT_ID, showQrModal: true }));
}

export const wagmiConfig = createConfig({
  chains: [sepolia],
  connectors,
  transports: {
    [sepolia.id]: http(RPC_URL),
  },
});

export type AppConnector = (typeof connectors)[number];
