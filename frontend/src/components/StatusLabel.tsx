import type { ReactNode } from "react";
import { Label } from "@primer/react";
import type { Tone } from "../api/types";
import { labelVariantForTone } from "../lib/tone";

export interface StatusLabelProps {
  /** Server-computed tone (UiFormat.status_tone / rate_tone); null renders a neutral label. */
  tone?: Tone;
  size?: "small" | "large";
  children: ReactNode;
  className?: string;
}

export function StatusLabel({ tone = null, size = "small", children, className }: StatusLabelProps) {
  return (
    <Label variant={labelVariantForTone(tone)} size={size} className={className}>
      {children}
    </Label>
  );
}

/** "Active" (green) or "Paused" (yellow). */
export function StandupStatusLabel({ active, size }: { active: boolean; size?: "small" | "large" }) {
  return (
    <StatusLabel tone={active ? "success" : "warning"} size={size}>
      {active ? "Active" : "Paused"}
    </StatusLabel>
  );
}
