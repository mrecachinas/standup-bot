import { useState } from "react";
import { useParams, useSearchParams } from "react-router";
import { Button } from "@primer/react";
import { del } from "../../api/client";
import type { ScheduleExceptionParams, ScheduleExceptionResult, ScheduleExceptionsPayload, ScheduleOccurrence } from "../../api/types/roster";
import { ErrorBanner, StandupHeader } from "../../components";
import { useMutation } from "../../hooks/useMutation";
import { MoveNextRunCard, RegularScheduleCard, SkipDateCard } from "./roster/ScheduleCards";
import { createScheduleException } from "./roster/schedule";
import { ExceptionsTable, UpcomingRunsSection } from "./roster/ScheduleLists";
import { SettingsLayout } from "./settings/SettingsLayout";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";
import styles from "./roster/roster.module.css";

export function ScheduleExceptionsPage() {
  const { id = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const requestedTimezone = searchParams.get("preview_timezone") ?? "";
  const base = `/api/standups/${id}/schedule_exceptions`;
  const { data, error, loading, reload, setStandup } = useStandupPage<ScheduleExceptionsPayload>(
    requestedTimezone ? `${base}?preview_timezone=${encodeURIComponent(requestedTimezone)}` : base,
    "Schedule",
  );

  // Quick actions (skip a row, cancel the next run, remove) report errors at the top.
  const [skipping, setSkipping] = useState<string | null>(null);
  const create = useMutation((params: ScheduleExceptionParams) => createScheduleException(id, params), { onSuccess: () => reload() });
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

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Schedule" />;

  const { standup } = data;

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="settings" onStandupChange={setStandup} />

      <SettingsLayout standupId={standup.id} section="schedule">
        <div className={layout.stack}>
          {error && !loading && <ErrorBanner error={error} title="Couldn't refresh the schedule" action={<Button onClick={reload}>Try again</Button>} />}
          <ErrorBanner error={create.error} title="Couldn't save the exception" onDismiss={create.reset} />
          <ErrorBanner error={remove.error} title="Couldn't remove the exception" onDismiss={remove.reset} />

          <div className={layout.mainAside}>
            <div className={layout.stack}>
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

            <aside className={layout.stack} aria-label="Schedule changes">
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
