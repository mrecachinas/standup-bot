import type { Tone } from "../api/types";
import styles from "./StatusDot.module.css";

/** A small coloured dot. With a `label` it's announced; without, it's decorative. */
export function StatusDot({ tone, label }: { tone: Tone; label?: string }) {
  return (
    <span
      className={styles.dot}
      data-tone={tone ?? undefined}
      role={label ? "img" : undefined}
      aria-label={label}
      aria-hidden={label ? undefined : true}
      title={label}
    />
  );
}
