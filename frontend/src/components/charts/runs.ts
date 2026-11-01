import { formatShortDate, parseApiDate } from "../../lib/format";

export const CHART_WIDTH = 720;
export const RUN_SEGMENTS = ["completed", "skipped", "pending", "missed"] as const;

export interface RunBreakdown {
  /** "2026-10-02" (or a Date). */
  date: string | Date;
  completed: number;
  skipped: number;
  pending?: number;
  missed: number;
  completion_rate: number;
  expected?: number;
}

/** "Oct 2, 2026: 2 completed, 0 skipped, 2 missed (50%)" */
export function runSummary(run: RunBreakdown): string {
  const date = parseApiDate(run.date);
  const pending = toInt(run.pending) > 0 ? `, ${run.pending} pending` : "";
  return `${date ? formatShortDate(date, true) : String(run.date)}: ${run.completed} completed, ${run.skipped} skipped, ${run.missed} missed${pending} (${Math.round(run.completion_rate)}%)`;
}

export function toInt(value: number | undefined | null): number {
  return Math.trunc(Number(value) || 0);
}
