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

/** Fire-and-forget webhook notifier (Telegram bot / generic JSON). Never throws into the poll loop. */
export function notifyWebhook(url: string | undefined, alert: Alert): void {
  if (!url) return;
  fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ text: `[${alert.level}] ${alert.message} (${alert.at})`, alert }),
  }).catch((e) => console.error(`webhook failed: ${(e as Error).message}`));
}

/**
 * Telegram bot notifier via Bot API sendMessage.
 * Only WARN/CRITICAL are pushed; INFO is skipped to avoid noise.
 * Never throws into the poll loop.
 */
export function notifyTelegram(botToken: string | undefined, chatId: string | undefined, alert: Alert): void {
  if (!botToken || !chatId) return;
  if (alert.level === "INFO") return;
  const text = `[${alert.level}] ${alert.message}\n${alert.at}`;
  const url = `https://api.telegram.org/bot${botToken}/sendMessage`;
  fetch(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, disable_web_page_preview: true }),
  }).catch((e) => console.error(`telegram push failed: ${(e as Error).message}`));
}

