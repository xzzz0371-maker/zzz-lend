// Minimal web stub for @react-native-async-storage/async-storage.
// The MetaMask SDK imports this; we never actually use the MetaMask connector.
const store = new Map();
export default {
  getItem: async (key) => (store.has(key) ? store.get(key) : null),
  setItem: async (key, value) => {
    store.set(key, String(value));
  },
  removeItem: async (key) => {
    store.delete(key);
  },
  clear: async () => {
    store.clear();
  },
};
