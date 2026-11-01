import type { Tone } from "../api/types";

export type LabelVariant = "default" | "success" | "accent" | "attention" | "danger";

const VARIANTS: Record<NonNullable<Tone>, LabelVariant> = {
  success: "success",
  info: "accent",
  warning: "attention",
  danger: "danger",
};

export function labelVariantForTone(tone: Tone | undefined): LabelVariant {
  return tone ? VARIANTS[tone] : "default";
}
