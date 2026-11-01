import type { ScheduleOccurrence } from "../../../api/types/standups";
import styles from "./standups.module.css";

/** A calendar-page tile: "OCT / 2". */
export function DateTile({ month, day }: { month: string; day: number }) {
  return (
    <span className={styles.dateTile} aria-hidden="true">
      <span className={styles.dateTileMonth}>{month}</span>
      <span className={styles.dateTileDay}>{day}</span>
    </span>
  );
}

/** Upcoming runs as date tiles with the weekday and local time. */
export function OccurrenceList({ occurrences, label = "Upcoming runs" }: { occurrences: ScheduleOccurrence[]; label?: string }) {
  return (
    <ul className={styles.list} aria-label={label}>
      {occurrences.map((occurrence) => (
        <li key={occurrence.scheduled_at}>
          <DateTile month={occurrence.month} day={occurrence.day} />
          <time dateTime={occurrence.scheduled_at} title={occurrence.label} className={styles.grow}>
            <div className={styles.title}>{occurrence.weekday}</div>
            <div className={styles.sub}>{occurrence.time}</div>
          </time>
        </li>
      ))}
    </ul>
  );
}
