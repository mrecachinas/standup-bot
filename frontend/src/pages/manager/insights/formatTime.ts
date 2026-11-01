import { formatShortDate, parseApiDate } from "../../../lib/format";

/** "Oct 30, 5:00 PM" (strftime "%b %-d, %-l:%M %p") in the browser's time zone. */
export function formatShortDateTime(value: string | null | undefined): string {
  const date = parseApiDate(value);
  if (!date) return "—";
  return `${formatShortDate(date)}, ${date.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })}`;
}
