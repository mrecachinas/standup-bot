import { useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { Button } from "@primer/react";
import { del, post } from "../../api/client";
import type { Standup } from "../../api/types";
import type {
  ScheduleExceptionParams,
  ScheduleExceptionResult,
  ScheduleExceptionsPayload,
  ScheduleOccurrence,
} from "../../api/types/roster";
import { ErrorBanner, LoadingState, StandupHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useMutation } from "../../hooks/useMutation";
import { MoveNextRunCard, RegularScheduleCard, SkipDateCard } from "./roster/ScheduleCards";
import { ExceptionsTable, UpcomingRunsSection } from "./roster/ScheduleLists";
import { StandupLoadError } from "./roster/StandupLoadError";
import { usePauseResume } from "./roster/usePauseResume";
import { SettingsLayout } from "./settings/SettingsLayout";
import styles from "./roster/roster.module.css";

export function ScheduleExceptionsPage() {
  const { id = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const requestedTimezone = searchParams.get("preview_timezone") ?? "";
  const base = `/api/standups/${id}/schedule_exceptions`;
  const { data, error, loading, reload, setData } = useApi<ScheduleExceptionsPayload>(
    requestedTimezone ? `${base}?preview_timezone=${encodeURIComponent(requestedTimezone)}` : base,
  );
  useDocumentTitle(data ? `Schedule · ${data.standup.name}` : "Schedule");

  const pauseResume = usePauseResume(data?.standup, (standup: Standup) => setData((current) => ({ ...(current as ScheduleExceptionsPayload), standup })));

  // Quick actions (skip a row, cancel the next run, remove) report errors at the top.
  const [skipping, setSkipping] = useState<string | null>(null);
  const create = useMutation((params: ScheduleExceptionParams) => post<ScheduleExceptionResult>(base, { schedule_exception: params }), {
    onSuccess: () => reload(),
  });
  const [removing, setRemoving] = useState<number | null>(null);
  const remove = useMutation((exceptionId: number) => del<ScheduleExceptionResult>(`${base}/${exceptionId}`), {
    onSuccess: () => reload(),
  });

  const handleSkip = async (occurrence: ScheduleOccurrence) => {
    remove.reset();
    setSkipping(occurrence.standup_date);
    await create.run({ exception_type: "skipped_date", original_date: occurrence.standup_date, reason: "Skipped" });
    setSkipping(null);
  };

  const handleCancelRun = (next: ScheduleOccurrence) => {
    remove.reset();
    return create.run({ exception_type: "cancelled", original_date: next.standup_date, reason: "One-off cancellation" });
  };

  const handleRemove = async (exceptionId: number) => {
    create.reset();
    setRemoving(exceptionId);
    await remove.run(exceptionId);
    setRemoving(null);
  };

  const handlePreviewTimezone = (timezone: string) => {
    setSearchParams(
      (params) => {
        const next = new URLSearchParams(params);
        if (timezone && timezone !== data?.default_exception_timezone) next.set("preview_timezone", timezone);
        else next.delete("preview_timezone");
        return next;
      },
      { replace: true },
    );
  };

  if (!data) {
    if (error) return <StandupLoadError error={error} title="Schedule" onRetry={reload} />;
    return <LoadingState label="Loading schedule…" />;
  }

  const { standup } = data;

  return (
    <div className={styles.page}>
      <StandupHeader standup={standup} active="settings" onPauseResume={pauseResume.toggle} pauseResumeBusy={pauseResume.busy} />

      <SettingsLayout standupId={standup.id} section="schedule">
        <div className={styles.stack}>
          {error && !loading && <ErrorBanner error={error} title="Couldn't refresh the schedule" action={<Button onClick={reload}>Try again</Button>} />}
          <ErrorBanner error={create.error} title="Couldn't save the exception" onDismiss={create.reset} />
          <ErrorBanner error={remove.error} title="Couldn't remove the exception" onDismiss={remove.reset} />

          <div className={styles.mainAside}>
            <div className={styles.stack}>
              <UpcomingRunsSection
                occurrences={data.upcoming_occurrences}
                previewTimezone={data.preview_timezone}
                timeZoneOptions={data.time_zone_options}
                onPreviewTimezoneChange={handlePreviewTimezone}
                skipping={skipping}
                onSkip={(occurrence) => void handleSkip(occurrence)}
                removing={removing}
                onUnskip={(exceptionId) => void handleRemove(exceptionId)}
              />
              <ExceptionsTable exceptions={data.schedule_exceptions} removing={removing} onRemove={(exception) => void handleRemove(exception.id)} />
            </div>

            <aside className={styles.stack} aria-label="Schedule changes">
              <RegularScheduleCard standup={standup} />
              <SkipDateCard standupId={standup.id} options={data.exception_type_options} onSaved={reload} />
              <MoveNextRunCard
                standupId={standup.id}
                next={data.next_occurrence}
                previewTimezone={data.preview_timezone}
                timeZoneOptions={data.time_zone_options}
                onSaved={reload}
                onCancelRun={handleCancelRun}
              />
              {data.notes.length > 0 && (
                <ul className={styles.notes}>
                  {data.notes.map((note) => (
                    <li key={note}>{note}</li>
                  ))}
                </ul>
              )}
            </aside>
          </div>
        </div>
      </SettingsLayout>
    </div>
  );
}
