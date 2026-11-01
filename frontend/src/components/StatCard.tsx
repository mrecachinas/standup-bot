import type { ReactNode } from "react";
import { clsx } from "clsx";
import type { Icon } from "@primer/octicons-react";
import type { Tone } from "../api/types";
import styles from "./StatCard.module.css";

export interface StatCardProps {
  label: ReactNode;
  value: ReactNode;
  /** Small text under the value, e.g. "of 12 expected". */
  hint?: ReactNode;
  /** Colours the value (e.g. a completion rate's rate_tone). */
  tone?: Tone;
  icon?: Icon;
  /** Extra content under the hint, e.g. a <Sparkline>. */
  children?: ReactNode;
  className?: string;
}

export function StatCard({ label, value, hint, tone = null, icon: IconComponent, children, className }: StatCardProps) {
  return (
    <div className={clsx(styles.card, className)}>
      <div className={styles.label}>
        {IconComponent && <IconComponent size={14} />}
        {label}
      </div>
      <div className={clsx(styles.value, tone && styles[tone])}>{value}</div>
      {hint && <div className={styles.hint}>{hint}</div>}
      {children}
    </div>
  );
}

/** Responsive grid for a row of StatCards. */
export function StatGrid({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={clsx(styles.grid, className)}>{children}</div>;
}
