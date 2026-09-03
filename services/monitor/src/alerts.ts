// Lightweight alert store with edge-trigger (only fires on state transitions).
export interface Alert {
  level: "INFO" | "WARN" | "CRITICAL";
  key: string;
  message: string;
  at: string;
}

export class AlertStore {
  private prev = new Map<string, boolean>();
  private out: (a: Alert) => void;

  constructor(out: (a: Alert) => void) {
    this.out = out;
  }

  /** Set current boolean state of `key`; emits alert only when `state` flips to true (or first seen true). */
  set(key: string, level: Alert["level"], active: boolean, message: string): void {
    const prev = this.prev.get(key) ?? false;
    if (active && !prev) {
      this.out({ level, key, message, at: new Date().toISOString() });
    }
    this.prev.set(key, active);
  }

  reset(): void {
    this.prev.clear();
  }
}
