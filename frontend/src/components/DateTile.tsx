import { clsx } from "clsx";
import { formatShortDate, parseApiDate } from "../lib/format";
import styles from "./DateTile.module.css";

/** A calendar tile ("OCT" over "2") for an ISO date. Decorative: pair it with a written date. */
export function DateTile({ date, blocked = false }: { date: string; blocked?: boolean }) {
  const parsed = parseApiDate(date);
  if (!parsed) return null;
  const [month] = formatShortDate(parsed).split(" ");

  return (
    <span className={clsx(styles.tile, blocked && styles.blocked)} aria-hidden="true">
      <span className={styles.month}>{month}</span>
      <span className={styles.day}>{parsed.getDate()}</span>
    </span>
  );
}
