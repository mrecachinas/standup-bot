import { formatDateTime, formatRelativeTime, parseApiDate } from "../lib/format";

export interface RelativeTimeProps {
  datetime: string | Date | null | undefined;
  /** Shown when there's no date (default "—"). */
  fallback?: string;
  /** Override "now" (tests). */
  now?: Date;
  className?: string;
}

/** "in 3 hours" / "2 days ago", with the full date and time as a tooltip. */
export function RelativeTime({ datetime, fallback = "—", now, className }: RelativeTimeProps) {
  const date = parseApiDate(datetime);
  if (!date) return <span className={className}>{fallback}</span>;

  return (
    <time className={className} dateTime={date.toISOString()} title={formatDateTime(date)}>
      {formatRelativeTime(date, now)}
    </time>
  );
}
