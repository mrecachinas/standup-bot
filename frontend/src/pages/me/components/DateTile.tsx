import { formatShortDate, parseApiDate } from "../../../components";
import styles from "./me.module.css";

/** A small calendar tile: "OCT" over "2". Decorative; the full date is shown next to it. */
export function DateTile({ date }: { date: string }) {
  const parsed = parseApiDate(date);
  if (!parsed) return null;
  const [month] = formatShortDate(parsed).split(" ");

  return (
    <span className={styles.dateTile} aria-hidden="true">
      <span className={styles.dateTileMonth}>{month}</span>
      <span className={styles.dateTileDay}>{parsed.getDate()}</span>
    </span>
  );
}
