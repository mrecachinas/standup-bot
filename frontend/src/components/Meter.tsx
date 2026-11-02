import type { ReactNode } from "react";
import { clsx } from "clsx";
import { ProgressBar } from "@primer/react";
import type { Tone } from "../api/types";
import { progressBgForTone } from "../lib/tone";
import styles from "./Meter.module.css";

export interface MeterProps {
  /** Percentage, clamped to 0–100. */
  value: number;
  tone: Tone | undefined;
  /** Accessible name for the bar, e.g. "Ada completion rate". */
  label: string;
  /** Text after the bar, e.g. "75%". */
  children: ReactNode;
  /** Spoken value when it differs from the visible text. */
  valueText?: string;
  className?: string;
}

/** A progress bar coloured by a server tone, with its value beside it. */
export function Meter({ value, tone, label, children, valueText, className }: MeterProps) {
  return (
    <span className={clsx(styles.meter, className)}>
      <ProgressBar
        className={styles.bar}
        progress={Math.min(100, Math.max(0, value))}
        bg={progressBgForTone(tone)}
        aria-label={label}
        aria-valuetext={valueText}
      />
      <span className={styles.value}>{children}</span>
    </span>
  );
}
