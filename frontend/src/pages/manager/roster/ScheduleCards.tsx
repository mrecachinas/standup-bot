import { useState, type FormEvent } from "react";
import { Link as RouterLink } from "react-router";
import { Button, FormControl, Select, TextInput } from "@primer/react";
import { PauseIcon, PencilIcon, PlayIcon } from "@primer/octicons-react";
import { post } from "../../../api/client";
import type { Standup } from "../../../api/types";
import type { ScheduleExceptionParams, ScheduleExceptionResult, ScheduleExceptionsPayload, ScheduleOccurrence } from "../../../api/types/roster";
import { ConfirmButton } from "../../../components";
import { useMutation } from "../../../hooks/useMutation";
import { paths } from "../../../paths";
import { baseMessages, fieldMessage } from "./formErrors";
import { MessagesBanner } from "./MessagesBanner";
import { Section, SectionBody } from "./Section";
import styles from "./roster.module.css";

export function RegularScheduleCard({ standup, onPauseResume, busy }: { standup: Standup; onPauseResume: () => void; busy: boolean }) {
  return (
    <Section
      title="Regular schedule"
      actions={
        <Button as={RouterLink} to={`${paths.editStandup(standup.id)}#schedule`} size="small" variant="invisible" leadingVisual={PencilIcon}>
          Edit
        </Button>
      }
    >
      <SectionBody>
        <p style={{ margin: 0 }}>{standup.schedule_summary}</p>
        <p className={styles.hint}>Pausing stops all runs until you resume. Saved exceptions are kept.</p>
        <div>
          <Button size="small" leadingVisual={standup.active ? PauseIcon : PlayIcon} onClick={onPauseResume} loading={busy}>
            {standup.active ? "Pause standup" : "Resume standup"}
          </Button>
        </div>
      </SectionBody>
    </Section>
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
  const save = useMutation(
    (params: ScheduleExceptionParams) => post<ScheduleExceptionResult>(`/api/standups/${standupId}/schedule_exceptions`, { schedule_exception: params }),
    {
      onSuccess: () => {
        setDate("");
        setReason("");
        onSaved();
      },
    },
  );

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    void save.run({ exception_type: type, original_date: date, reason: reason.trim() });
  };

  const dateError = fieldMessage(save.error, "original_date", "Date");
  const typeError = fieldMessage(save.error, "exception_type", "Type");
  const reasonError = fieldMessage(save.error, "reason", "Reason");

  return (
    <Section title="Skip a date" titleId="skip-date-heading">
      <SectionBody>
        <form className={styles.stack} onSubmit={handleSubmit} aria-labelledby="skip-date-heading" noValidate>
          <MessagesBanner title="Couldn't save the exception" messages={baseMessages(save.error, SKIP_FIELDS)} onDismiss={save.reset} />
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
      </SectionBody>
    </Section>
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
    <Section
      title="Move the next run"
      titleId="move-run-heading"
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
        <p className={styles.emptyInline}>There's no upcoming run to move.</p>
      )}
    </Section>
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
  const zones = timeZoneOptions.includes(previewTimezone) ? timeZoneOptions : [previewTimezone, ...timeZoneOptions];

  const save = useMutation(
    (params: ScheduleExceptionParams) => post<ScheduleExceptionResult>(`/api/standups/${standupId}/schedule_exceptions`, { schedule_exception: params }),
    { onSuccess: () => onSaved() },
  );

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
    <SectionBody>
      <form className={styles.stack} onSubmit={handleSubmit} aria-labelledby="move-run-heading" noValidate>
        <p className={styles.hint}>
          Currently <strong>{next.local_label}</strong>.
        </p>
        <MessagesBanner
          title="Couldn't move the run"
          messages={[...(originalError ? [originalError] : []), ...baseMessages(save.error, MOVE_FIELDS)]}
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
    </SectionBody>
  );
}
