import { Label } from "@primer/react";
import { ArrowDownIcon, ArrowUpIcon } from "@primer/octicons-react";

export interface CompletionDeltaProps {
  /** Percentage points against the previous period of the same length. */
  value: number | null;
  direction: "up" | "down" | "flat" | null;
}

/** "↑ 5 pts" against the previous period of the same length. */
export function CompletionDelta({ value, direction }: CompletionDeltaProps) {
  if (value === null || !direction) return null;

  const variant = direction === "up" ? "success" : direction === "down" ? "danger" : "secondary";
  return (
    <Label variant={variant} title="Compared with the previous period" style={{ gap: "var(--base-size-2)", fontVariantNumeric: "tabular-nums" }}>
      {direction === "up" && <ArrowUpIcon size={12} aria-label="Up" />}
      {direction === "down" && <ArrowDownIcon size={12} aria-label="Down" />}
      {Math.abs(value)} pts
    </Label>
  );
}
