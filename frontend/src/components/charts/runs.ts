import type { RunTotals } from "../../api/types";
import { formatShortDate, parseApiDate } from "../../lib/format";

export const CHART_WIDTH = 720;
export const RUN_SEGMENTS = ["completed", "skipped", "pending", "missed"] as const;

/** "Oct 2, 2026: 2 completed, 0 skipped, 2 missed (50%)" */
export function runSummary(run: RunTotals): string {
  const date = parseApiDate(run.date);
  const pending = run.pending > 0 ? `, ${run.pending} pending` : "";
  return `${date ? formatShortDate(date, true) : run.date}: ${run.completed} completed, ${run.skipped} skipped, ${run.missed} missed${pending} (${Math.round(run.completion_rate)}%)`;
}
