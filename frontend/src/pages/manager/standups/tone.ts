import type { Tone } from "../../../api/types";

const PROGRESS_BG: Record<NonNullable<Tone>, string> = {
  success: "success",
  info: "accent",
  warning: "attention",
  danger: "danger",
};

/** ProgressBar's `bg` ("success" → --bgColor-success-emphasis) for a server tone. */
export function progressBgForTone(tone: Tone | undefined): string {
  return tone ? PROGRESS_BG[tone] : "neutral";
}
