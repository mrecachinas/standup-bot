import { Button, FormControl, Select, VisuallyHidden } from "@primer/react";
import { DataTable, Table } from "@primer/react/experimental";
import { CalendarIcon } from "@primer/octicons-react";
import type { ScheduleException, ScheduleOccurrence } from "../../../api/types/roster";
import { DateTile, EmptyState, Panel, StatusLabel } from "../../../components";
import layout from "../../../styles/layout.module.css";
import { zoneOptions } from "./schedule";

export interface UpcomingRunsSectionProps {
  occurrences: ScheduleOccurrence[];
  previewTimezone: string;
  timeZoneOptions: string[];
  onPreviewTimezoneChange: (timezone: string) => void;
  /** Date (standup_date) currently being skipped. */
  skipping: string | null;
  onSkip: (occurrence: ScheduleOccurrence) => void;
  /** Exception id currently being removed. */
  removing: number | null;
  onUnskip: (exceptionId: number) => void;
}

export function UpcomingRunsSection({
  occurrences,
  previewTimezone,
  timeZoneOptions,
  onPreviewTimezoneChange,
  skipping,
  onSkip,
  removing,
  onUnskip,
}: UpcomingRunsSectionProps) {
  const zones = zoneOptions(timeZoneOptions, previewTimezone);

  return (
    <Panel
      title="Upcoming runs"
      headingId="upcoming-runs-heading"
      description="Includes skipped and moved dates"
      flush
      actions={
        <FormControl>
          <FormControl.Label visuallyHidden>Show times in</FormControl.Label>
          <Select name="preview_timezone" size="small" value={previewTimezone} onChange={(event) => onPreviewTimezoneChange(event.target.value)}>
            {zones.map((zone) => (
              <Select.Option key={zone} value={zone}>
                {zone}
              </Select.Option>
            ))}
          </Select>
        </FormControl>
      }
    >
      {occurrences.length > 0 ? (
        <ul className={layout.list} aria-labelledby="upcoming-runs-heading">
          {occurrences.map((occurrence) => (
            <li key={occurrence.scheduled_at + occurrence.standup_date}>
              <DateTile date={occurrence.local_date} blocked={occurrence.blocked} />
              <div className={layout.grow}>
                <div className={occurrence.blocked ? layout.muted : undefined}>
                  <time dateTime={occurrence.scheduled_at}>{occurrence.local_label}</time>
                </div>
                {occurrence.note && <div className={layout.hint}>{occurrence.note}</div>}
              </div>
              <StatusLabel tone={occurrence.status_tone}>{occurrence.status_label}</StatusLabel>
              {occurrence.can_skip && (
                <Button
                  size="small"
                  aria-label={`Skip ${occurrence.standup_date_label}`}
                  loading={skipping === occurrence.standup_date}
                  disabled={skipping !== null && skipping !== occurrence.standup_date}
                  onClick={() => onSkip(occurrence)}
                >
                  Skip
                </Button>
              )}
              {occurrence.can_unskip && occurrence.exception_id !== null && (
                <Button
                  size="small"
                  aria-label={`Unskip ${occurrence.standup_date_label}`}
                  loading={removing === occurrence.exception_id}
                  onClick={() => onUnskip(occurrence.exception_id!)}
                >
                  Unskip
                </Button>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <p className={layout.empty}>No upcoming occurrences could be calculated for this schedule.</p>
      )}
    </Panel>
  );
}

export interface ExceptionsTableProps {
  exceptions: ScheduleException[];
  removing: number | null;
  onRemove: (exception: ScheduleException) => void;
}

export function ExceptionsTable({ exceptions, removing, onRemove }: ExceptionsTableProps) {
  return (
    <Table.Container>
      <Table.Title as="h2" id="exceptions-heading">
        Exceptions
      </Table.Title>
      {exceptions.length > 0 ? (
        <DataTable
          aria-labelledby="exceptions-heading"
          data={exceptions}
          columns={[
            { header: "Date", field: "original_date_label", rowHeader: true, width: "auto" },
            {
              header: "Type",
              id: "type",
              width: "auto",
              renderCell: (row) => <StatusLabel tone={row.tone}>{row.label}</StatusLabel>,
            },
            {
              header: "Moved to",
              id: "moved_to",
              width: "auto",
              renderCell: (row) => row.scheduled_at_label ?? <span className={layout.muted}>—</span>,
            },
            {
              header: "Reason",
              id: "reason",
              width: "growCollapse",
              renderCell: (row) => row.reason || <span className={layout.muted}>—</span>,
            },
            {
              header: () => <VisuallyHidden>Actions</VisuallyHidden>,
              id: "actions",
              align: "end",
              width: "auto",
              renderCell: (row) => (
                <Button
                  size="small"
                  variant="invisible"
                  loading={removing === row.id}
                  aria-label={`Remove the ${row.label.toLowerCase()} exception for ${row.original_date_label}`}
                  onClick={() => onRemove(row)}
                >
                  Remove
                </Button>
              ),
            },
          ]}
        />
      ) : (
        <EmptyState icon={CalendarIcon} headingLevel="h3" size="small" title="No exceptions" description="No skipped, holiday, or moved dates yet." />
      )}
    </Table.Container>
  );
}
