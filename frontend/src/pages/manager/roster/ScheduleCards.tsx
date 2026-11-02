import { useState, type FormEvent } from "react";
import { Link as RouterLink } from "react-router";
import { Button, FormControl, Select, TextInput } from "@primer/react";
import { PauseIcon, PencilIcon, PlayIcon } from "@primer/octicons-react";
import type { Standup } from "../../../api/types";
import type { ScheduleExceptionParams, ScheduleExceptionsPayload, ScheduleOccurrence } from "../../../api/types/roster";
import { ConfirmButton, ErrorBanner, Panel, PanelBody } from "../../../components";
import { useMutation } from "../../../hooks/useMutation";
import { usePauseResume } from "../../../hooks/usePauseResume";
import { baseMessages, fieldMessage } from "../../../lib/fieldErrors";
import { paths } from "../../../paths";
import layout from "../../../styles/layout.module.css";
import { createScheduleException, zoneOptions } from "./schedule";

export function RegularScheduleCard({ standup, onStandupChange }: { standup: Standup; onStandupChange: (standup: Standup) => void }) {
  const pauseResume = usePauseResume(onStandupChange);
  return (
    <Panel
      title="Regular schedule"
      actions={
        <Button as={RouterLink} to={`${paths.editStandup(standup.id)}#schedule`} size="small" variant="invisible" leadingVisual={PencilIcon}>
          Edit
        </Button>
      }
    >
      <p style={{ margin: 0 }}>{standup.schedule_summary}</p>
      <p className={layout.hint}>Pausing stops all runs until you resume. Saved exceptions are kept.</p>
      <div>
        <Button size="small" leadingVisual={standup.active ? PauseIcon : PlayIcon} onClick={() => void pauseResume.run(standup)} loading={pauseResume.loading}>
          {standup.active ? "Pause standup" : "Resume standup"}
        </Button>
      </div>
    </Panel>
  );
}

const SKIP_FIELDS = ["original_date", "exception_type", "reason"];

export function SkipDateCard({
  standupId,
  options,
  onSaved,
}: {
  standupId: number;
  options: ScheduleExceptionsPayload["exception_type_options"];
  onSaved: () => void;
}) {
  const [date, setDate] = useState("");
  const [type, setType] = useState(options[0]?.value ?? "skipped_date");
  const [reason, setReason] = useState("");
  const save = useMutation((params: ScheduleExceptionParams) => createScheduleException(standupId, params), {
    onSuccess: () => {
      setDate("");
      setReason("");
      onSaved();
    },
  });

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void save.run({ exception_type: type, original_date: date, reason: reason.trim() });
  };

  const dateError = fieldMessage(save.error, "original_date", "Date");
  const typeError = fieldMessage(save.error, "exception_type", "Type");
  const reasonError = fieldMessage(save.error, "reason", "Reason");

  return (
    <Panel title="Skip a date" headingId="skip-date-heading">
      <form className={layout.stack} onSubmit={handleSubmit} aria-labelledby="skip-date-heading" noValidate>
        <ErrorBanner title="Couldn't save the exception" error={baseMessages(save.error, SKIP_FIELDS)} onDismiss={save.reset} />
        <FormControl required>
          <FormControl.Label>Date</FormControl.Label>
          <TextInput type="date" name="original_date" value={date} onChange={(event) => setDate(event.target.value)} block />
          {dateError && <FormControl.Validation variant="error">{dateError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Type</FormControl.Label>
          <Select name="exception_type" value={type} onChange={(event) => setType(event.target.value as typeof type)} block>
            {options.map((option) => (
              <Select.Option key={option.value} value={option.value}>
                {option.label}
              </Select.Option>
            ))}
          </Select>
          {typeError && <FormControl.Validation variant="error">{typeError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Reason</FormControl.Label>
          <TextInput name="reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Company holiday, offsite…" block />
          {reasonError && <FormControl.Validation variant="error">{reasonError}</FormControl.Validation>}
        </FormControl>
        <Button type="submit" variant="primary" loading={save.loading} disabled={!date} block>
          Save exception
        </Button>
      </form>
    </Panel>
  );
}

const MOVE_FIELDS = ["rescheduled_date", "rescheduled_time", "rescheduled_timezone", "reason", "original_date"];

export interface MoveNextRunCardProps {
  standupId: number;
  next: ScheduleOccurrence | null;
  previewTimezone: string;
  timeZoneOptions: string[];
  onSaved: () => void;
  /** Cancels the next run (a "cancelled" exception); errors show at the top of the page. */
  onCancelRun: (next: ScheduleOccurrence) => Promise<unknown>;
}

export function MoveNextRunCard({ standupId, next, previewTimezone, timeZoneOptions, onSaved, onCancelRun }: MoveNextRunCardProps) {
  return (
    <Panel
      title="Move the next run"
      headingId="move-run-heading"
      flush
      footer={
        next && (
          <ConfirmButton
            size="small"
            variant="danger"
            title="Cancel the next run?"
            message={`Cancel the run on ${next.local_short_label}?`}
            confirmLabel="Cancel run"
            cancelLabel="Keep it"
            danger
            onConfirm={() => onCancelRun(next)}
          >
            Cancel next run
          </ConfirmButton>
        )
      }
    >
      {next ? (
        // Re-mount when the next run or preview timezone changes so the defaults follow.
        <MoveForm
          key={`${next.standup_date}|${previewTimezone}`}
          standupId={standupId}
          next={next}
          previewTimezone={previewTimezone}
          timeZoneOptions={timeZoneOptions}
          onSaved={onSaved}
        />
      ) : (
        <p className={layout.empty}>There's no upcoming run to move.</p>
      )}
    </Panel>
  );
}

function MoveForm({
  standupId,
  next,
  previewTimezone,
  timeZoneOptions,
  onSaved,
}: Omit<MoveNextRunCardProps, "next" | "onCancelRun"> & { next: ScheduleOccurrence }) {
  const [date, setDate] = useState(next.local_date);
  const [time, setTime] = useState(next.local_time);
  const [timezone, setTimezone] = useState(previewTimezone);
  const [reason, setReason] = useState("");
  const zones = zoneOptions(timeZoneOptions, previewTimezone);
  const save = useMutation((params: ScheduleExceptionParams) => createScheduleException(standupId, params), { onSuccess: () => onSaved() });

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void save.run({
      exception_type: "rescheduled",
      original_date: next.standup_date,
      rescheduled_date: date,
      rescheduled_time: time,
      rescheduled_timezone: timezone,
      reason: reason.trim(),
    });
  };

  const dateError = fieldMessage(save.error, "rescheduled_date", "New date");
  const timeError = fieldMessage(save.error, "rescheduled_time", "New time");
  const zoneError = fieldMessage(save.error, "rescheduled_timezone", "Timezone");
  const reasonError = fieldMessage(save.error, "reason", "Reason");
  const originalError = fieldMessage(save.error, "original_date", "Original date");

  return (
    <PanelBody>
      <form className={layout.stack} onSubmit={handleSubmit} aria-labelledby="move-run-heading" noValidate>
        <p className={layout.hint}>
          Currently <strong>{next.local_label}</strong>.
        </p>
        <ErrorBanner
          title="Couldn't move the run"
          error={[...(originalError ? [originalError] : []), ...baseMessages(save.error, MOVE_FIELDS)]}
          onDismiss={save.reset}
        />
        <FormControl required>
          <FormControl.Label>New date</FormControl.Label>
          <TextInput type="date" name="rescheduled_date" value={date} onChange={(event) => setDate(event.target.value)} block />
          {dateError && <FormControl.Validation variant="error">{dateError}</FormControl.Validation>}
        </FormControl>
        <FormControl required>
          <FormControl.Label>New time</FormControl.Label>
          <TextInput type="time" name="rescheduled_time" value={time} onChange={(event) => setTime(event.target.value)} block />
          {timeError && <FormControl.Validation variant="error">{timeError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Timezone</FormControl.Label>
          <Select name="rescheduled_timezone" value={timezone} onChange={(event) => setTimezone(event.target.value)} block>
            {zones.map((zone) => (
              <Select.Option key={zone} value={zone}>
                {zone}
              </Select.Option>
            ))}
          </Select>
          {zoneError && <FormControl.Validation variant="error">{zoneError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Reason</FormControl.Label>
          <TextInput name="reason" value={reason} onChange={(event) => setReason(event.target.value)} placeholder="Team offsite" block />
          {reasonError && <FormControl.Validation variant="error">{reasonError}</FormControl.Validation>}
        </FormControl>
        <div>
          <Button type="submit" variant="primary" loading={save.loading} disabled={!date || !time}>
            Move run
          </Button>
        </div>
      </form>
    </PanelBody>
  );
}
