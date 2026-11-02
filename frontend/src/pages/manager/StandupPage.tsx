import { Link as RouterLink, useParams } from "react-router";
import { Button, Label } from "@primer/react";
import { InboxIcon } from "@primer/octicons-react";
import type { StandupOverviewPayload } from "../../api/types/standups";
import { Avatar, EmptyState, LoadingState, StandupHeader, StatCard, StatGrid, StatusLabel } from "../../components";
import { RunBreakdownChart, RunLegend } from "../../components/charts";
import { formatDateTime, formatShortDate, parseApiDate } from "../../lib/format";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { OccurrenceList } from "./standups/OccurrenceList";
import { Section } from "./standups/Section";
import { StandupLoadError } from "./standups/StandupLoadError";
import { usePauseResume } from "./standups/usePauseResume";
import styles from "./standups/standups.module.css";
import overviewStyles from "./standups/StandupOverview.module.css";

const UPCOMING_LIMIT = 4;

/** /manager/standups/:id: the standup's overview tab. */
export function StandupPage() {
  const { id = "" } = useParams();
  const { data, error, loading, reload, setData } = useApi<StandupOverviewPayload>(`/api/standups/${id}?include=overview`);
  useDocumentTitle(data?.standup.name ?? "Standup");
  const pauseResume = usePauseResume((result) => {
    setData((current) => ({ ...current!, standup: { ...current!.standup, ...result.standup } }));
    reload();
  });

  if (!data) {
    if (error) return <StandupLoadError error={error} onRetry={reload} />;
    return loading ? <LoadingState label="Loading standup…" /> : null;
  }

  const { standup, overview } = data;
  const { completion } = overview;
  const delta = completion.delta;

  return (
    <div className={styles.page}>
      <StandupHeader
        standup={standup}
        active="overview"
        onPauseResume={() => void pauseResume.run(standup.id, standup.active)}
        pauseResumeBusy={pauseResume.loading}
      />

      <StatGrid>
        <StatCard
          label={`Completion · ${overview.period_days} days`}
          value={
            <span className={overviewStyles.statValue}>
              {completion.label}
              {delta && (
                <Label variant={delta.direction === "up" ? "success" : delta.direction === "down" ? "danger" : "secondary"} title={delta.title}>
                  {delta.label}
                </Label>
              )}
            </span>
          }
          tone={completion.tone}
          hint={completion.sub_label}
        />
        <StatCard label="Avg. time to respond" value={overview.average_response_time.label} hint="From prompt to submitted" />
        <StatCard label="People" value={overview.participant_counts.active} hint={`${overview.participant_counts.inactive} inactive`} />
        <StatCard label="Next run" value={<span className={overviewStyles.smallValue}>{overview.next_run.label}</span>} hint={overview.next_run.sub_label} />
      </StatGrid>

      <div className={styles.mainAside}>
        <div className={styles.stack}>
          <Section
            title="Recent runs"
            hint={`Last ${overview.period_days} days`}
            actions={
              <>
                <RunLegend pending={overview.runs_have_pending} />
                <Button as={RouterLink} to={paths.standupAnalytics(standup.id)} size="small">
                  View insights
                </Button>
              </>
            }
          >
            <RunBreakdownChart runs={overview.runs} height={180} label={`Responses per run for ${standup.name}`} />
          </Section>

          <Section
            title="Latest run"
            hint={overview.latest_run.date_label}
            flush
            actions={
              <Button as={RouterLink} to={paths.standupResponses(standup.id)} size="small">
                All responses
              </Button>
            }
          >
            {overview.latest_run.responses.length > 0 ? (
              <ul className={styles.list} aria-label="Latest run responses">
                {overview.latest_run.responses.map((response) => (
                  <li key={response.id} className={styles.top}>
                    <Avatar name={response.display_name} src={response.avatar_url} />
                    <div className={styles.grow}>
                      <div className={styles.row}>
                        <span className={styles.title}>{response.display_name}</span>
                        <StatusLabel tone={response.status_tone}>{response.status_label}</StatusLabel>
                      </div>
                      {response.answers.length > 0 && (
                        <dl className={overviewStyles.answers}>
                          {response.answers.map((answer, index) => (
                            <div key={index} className={overviewStyles.answer}>
                              <dt>{answer.question}</dt>
                              <dd>{answer.answer}</dd>
                            </div>
                          ))}
                        </dl>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            ) : (
              <EmptyState icon={InboxIcon} title="No responses yet" description="Responses will show up here after the first run." border={false} size="small" headingLevel="h3" />
            )}
          </Section>
        </div>

        <aside className={styles.stack} aria-label="Standup details">
          <Section
            title="Questions"
            actions={
              <Button as={RouterLink} to={`${paths.editStandup(standup.id)}#questions`} size="small" variant="invisible">
                Edit
              </Button>
            }
          >
            {(standup.questions ?? []).length > 0 ? (
              <ol className={overviewStyles.questions}>
                {(standup.questions ?? []).map((question, index) => (
                  <li key={index}>{question}</li>
                ))}
              </ol>
            ) : (
              <p className={styles.muted}>No questions yet.</p>
            )}
          </Section>

          <Section
            title="Upcoming"
            flush
            actions={
              <Button as={RouterLink} to={paths.standupScheduleExceptions(standup.id)} size="small" variant="invisible">
                Schedule
              </Button>
            }
          >
            {overview.upcoming.paused ? (
              <p className={styles.inlineEmpty}>{overview.upcoming.paused_message}</p>
            ) : overview.upcoming.occurrences.length > 0 ? (
              <OccurrenceList occurrences={overview.upcoming.occurrences.slice(0, UPCOMING_LIMIT)} />
            ) : (
              <p className={styles.inlineEmpty}>{overview.upcoming.empty_message}</p>
            )}
          </Section>

          {overview.schedule_exceptions.length > 0 && (
            <Section
              title="Schedule exceptions"
              flush
              actions={
                <Button as={RouterLink} to={paths.standupScheduleExceptions(standup.id)} size="small" variant="invisible">
                  Manage
                </Button>
              }
            >
              <ul className={styles.list} aria-label="Schedule exceptions">
                {overview.schedule_exceptions.map((exception) => {
                  const original = parseApiDate(exception.original_date);
                  const rescheduled = parseApiDate(exception.rescheduled_at);
                  return (
                    <li key={exception.id}>
                      <div className={styles.grow}>
                        <div className={styles.row}>
                          <span className={styles.title}>{original ? formatShortDate(original, true) : "—"}</span>
                          <StatusLabel tone={exception.tone}>{exception.label}</StatusLabel>
                        </div>
                        {rescheduled && <div className={styles.sub}>Moved to {formatDateTime(rescheduled)}</div>}
                        {exception.reason && <div className={styles.sub}>{exception.reason}</div>}
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Section>
          )}

          <Section
            title="People"
            actions={
              <Button as={RouterLink} to={paths.standupParticipants(standup.id)} size="small" variant="invisible">
                Manage
              </Button>
            }
          >
            {overview.sidebar_participants.length > 0 ? (
              <>
                <ul className={overviewStyles.people} aria-label="Active participants">
                  {overview.sidebar_participants.map((participant) => (
                    <li key={participant.id}>
                      <Avatar name={participant.display_name} src={participant.avatar_url} size={24} />
                      <span className={overviewStyles.personName}>{participant.display_name}</span>
                      {participant.timezone_label && <span className={styles.sub}>{participant.timezone_label}</span>}
                    </li>
                  ))}
                </ul>
                {overview.more_participants_count > 0 && <p className={styles.sub}>{overview.more_participants_count} more</p>}
              </>
            ) : (
              <p className={styles.muted}>No one has been added yet.</p>
            )}
          </Section>
        </aside>
      </div>
    </div>
  );
}
