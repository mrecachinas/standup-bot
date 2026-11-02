import type { Tone } from "../api/types";

type Colour = "success" | "accent" | "attention" | "danger";

const COLOURS: Record<NonNullable<Tone>, Colour> = {
  success: "success",
  info: "accent",
  warning: "attention",
  danger: "danger",
};

/** Primer Label variant for a server tone; null is a neutral label. */
export function labelVariantForTone(tone: Tone | undefined): Colour | "default" {
  return tone ? COLOURS[tone] : "default";
}

/** ProgressBar `bg` for a server tone ("success" → --bgColor-success-emphasis); null is neutral. */
export function progressBgForTone(tone: Tone | undefined): Colour | "neutral" {
  return tone ? COLOURS[tone] : "neutral";
}
