import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  // Static HTML export for Cloudflare Pages (no SSR/Node runtime).
  output: "export",
  images: { unoptimized: true },
  trailingSlash: true,
  reactStrictMode: true,
  webpack(config) {
    config.resolve.alias = {
      ...config.resolve.alias,
      // MetaMask SDK pulls in react-native packages that are irrelevant on the web.
      "@react-native-async-storage/async-storage": path.resolve(__dirname, "stubs/async-storage.js"),
      "react-native": path.resolve(__dirname, "stubs/react-native.js"),
    };
    return config;
  },
};

export default nextConfig;
