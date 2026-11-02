import type { PreviewOccurrence } from "../../../api/types/standups";
import { DateTile } from "../../../components";
import layout from "../../../styles/layout.module.css";

/** Upcoming runs as date tiles with the weekday and local time. */
export function OccurrenceList({ occurrences, label = "Upcoming runs" }: { occurrences: PreviewOccurrence[]; label?: string }) {
  return (
    <ul className={layout.list} aria-label={label}>
      {occurrences.map((occurrence) => (
        <li key={occurrence.scheduled_at}>
          <DateTile date={occurrence.date} />
          <time dateTime={occurrence.scheduled_at} title={occurrence.label} className={layout.grow}>
            <div className={layout.title}>{occurrence.weekday}</div>
            <div className={layout.hint}>{occurrence.time}</div>
          </time>
        </li>
      ))}
    </ul>
  );
}
