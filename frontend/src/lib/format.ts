/** "75%" (rounded), or "—" when there's no value. */
export function formatPercent(value: number | null | undefined, digits = 0): string {
  if (value === null || value === undefined || Number.isNaN(value)) return "—";
  return `${value.toFixed(digits)}%`;
}

/** "1 participant", "3 participants". */
export function pluralize(count: number, singular: string, plural = `${singular}s`): string {
  return `${count} ${count === 1 ? singular : plural}`;
}

/** "Alice, Bob and Carol" (Rails' to_sentence). */
export function toSentence(items: string[]): string {
  if (items.length <= 1) return items.join("");
  return `${items.slice(0, -1).join(", ")} and ${items[items.length - 1]}`;
}

const UNITS: [Intl.RelativeTimeFormatUnit, number][] = [
  ["year", 365 * 24 * 3600],
  ["month", 30 * 24 * 3600],
  ["week", 7 * 24 * 3600],
  ["day", 24 * 3600],
  ["hour", 3600],
  ["minute", 60],
];

/** "in 3 hours", "2 days ago", "just now". */
export function formatRelativeTime(date: Date, now: Date = new Date()): string {
  const seconds = (date.getTime() - now.getTime()) / 1000;
  if (Math.abs(seconds) < 45) return "just now";

  const formatter = new Intl.RelativeTimeFormat("en", { numeric: "always" });
  for (const [unit, size] of UNITS) {
    if (Math.abs(seconds) >= size * 0.95 || unit === "minute") {
      return formatter.format(Math.round(seconds / size), unit);
    }
  }
  return formatter.format(Math.round(seconds / 60), "minute");
}

/** "Oct 2, 2026, 9:30 AM" in the browser's locale/time zone. */
export function formatDateTime(date: Date): string {
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

/**
 * Parses an API date ("2026-10-02") as a local calendar date, or a timestamp
 * as-is. Returns null for empty or invalid values.
 */
export function parseApiDate(value: string | Date | null | undefined): Date | null {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;

  const dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  const date = dateOnly ? new Date(Number(dateOnly[1]), Number(dateOnly[2]) - 1, Number(dateOnly[3])) : new Date(value);
  return Number.isNaN(date.getTime()) ? null : date;
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** "Oct 2" (strftime "%b %-d"), or "Oct 2, 2026" with the year. */
export function formatShortDate(date: Date, withYear = false): string {
  const base = `${MONTHS[date.getMonth()]} ${date.getDate()}`;
  return withYear ? `${base}, ${date.getFullYear()}` : base;
}

/** "Oct 30, 5:00 PM" in the browser's time zone, or "—" without a date. */
export function formatShortDateTime(value: string | null | undefined): string {
  const date = parseApiDate(value);
  if (!date) return "—";
  return `${formatShortDate(date)}, ${date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}`;
}
