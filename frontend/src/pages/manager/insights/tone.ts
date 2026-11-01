import type { Tone } from "../../../api/types";
import type { LabelProps } from "@primer/react";

/** ProgressBar `bg` for a server tone (rate_tone / status_tone). */
export function progressBgForTone(tone: Tone | undefined): string {
  switch (tone) {
    case "success":
      return "success.emphasis";
    case "warning":
      return "attention.emphasis";
    case "danger":
      return "danger.emphasis";
    case "info":
      return "accent.emphasis";
    default:
      return "neutral.emphasis";
  }
}

/** Label variant for a tone that may also be "accent" (admin access). */
export function labelVariant(tone: Tone | "accent" | undefined): NonNullable<LabelProps["variant"]> {
  switch (tone) {
    case "success":
      return "success";
    case "warning":
      return "attention";
    case "danger":
      return "danger";
    case "info":
    case "accent":
      return "accent";
    default:
      return "secondary";
  }
}
