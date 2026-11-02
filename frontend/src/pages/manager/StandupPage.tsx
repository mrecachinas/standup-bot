import { Link as RouterLink, useParams } from "react-router";
import { Button } from "@primer/react";
import { InboxIcon } from "@primer/octicons-react";
import type { StandupOverviewPayload } from "../../api/types/standups";
import { Avatar, CompletionDelta, EmptyState, Panel, StandupHeader, StatCard, StatGrid, StatusLabel } from "../../components";
import { RunBreakdownChart, RunLegend } from "../../components/charts";
import { formatDateTime, formatShortDate, parseApiDate } from "../../lib/format";
import { paths } from "../../paths";
import { OccurrenceList } from "./standups/OccurrenceList";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";
import styles from "./standups/StandupOverview.module.css";

const UPCOMING_LIMIT = 4;

/** /manager/standups/:id: the standup's overview tab. */
export function StandupPage() {
  const { id = "" } = useParams();
  const { data, error, reload, setStandup } = useStandupPage<StandupOverviewPayload>(`/api/standups/${id}?include=overview`, null);

  if (!data) return <StandupLoadState error={error} onRetry={reload} />;

  const { standup, overview } = data;
  const { completion } = overview;

  return (
    <div className={layout.page}>
      <StandupHeader
        standup={standup}
        active="overview"
        onStandupChange={(updated) => {
          setStandup(updated);
          reload();
        }}
      />

      <StatGrid>
        <StatCard
          label={`Completion · ${overview.period_days} days`}
          value={
            <>
              {completion.label}
              {completion.delta && <CompletionDelta value={completion.delta.value} direction={completion.delta.direction} />}
            </>
          }
          tone={completion.tone}
          hint={completion.sub_label}
        />
        <StatCard label="Avg. time to respond" value={overview.average_response_time.label} hint="From prompt to submitted" />
        <StatCard label="Participants" value={overview.participant_counts.active} hint={`${overview.participant_counts.inactive} inactive`} />
        <StatCard label="Next run" value={<span className={styles.smallValue}>{overview.next_run.label}</span>} hint={overview.next_run.sub_label} />
      </StatGrid>

      <div className={layout.mainAside}>
        <div className={layout.stack}>
          <Panel
            title="Recent runs"
            description={`Last ${overview.period_days} days`}
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
          </Panel>

          <Panel
            title="Latest run"
            description={overview.latest_run.date_label}
            flush
            actions={
              <Button as={RouterLink} to={paths.standupResponses(standup.id)} size="small">
                All responses
              </Button>
            }
          >
            {overview.latest_run.responses.length > 0 ? (
              <ul className={layout.list} aria-label="Latest run responses">
                {overview.latest_run.responses.map((response) => (
                  <li key={response.id} className={layout.top}>
                    <Avatar name={response.display_name} src={response.avatar_url} />
                    <div className={layout.grow}>
                      <div className={layout.row}>
                        <span className={layout.title}>{response.display_name}</span>
                        <StatusLabel tone={response.status_tone}>{response.status_label}</StatusLabel>
                      </div>
                      {response.answers.length > 0 && (
                        <dl className={styles.answers}>
                          {response.answers.map((answer, index) => (
                            <div key={index} className={styles.answer}>
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
          </Panel>
        </div>

        <aside className={layout.stack} aria-label="Standup details">
          <Panel
            title="Questions"
            actions={
              <Button as={RouterLink} to={`${paths.editStandup(standup.id)}#questions`} size="small" variant="invisible">
                Edit
              </Button>
            }
          >
            {standup.questions.length > 0 ? (
              <ol className={styles.questions}>
                {standup.questions.map((question, index) => (
                  <li key={index}>{question}</li>
                ))}
              </ol>
            ) : (
              <p className={layout.muted}>No questions yet.</p>
            )}
          </Panel>

          <Panel
            title="Upcoming"
            flush
            actions={
              <Button as={RouterLink} to={paths.standupScheduleExceptions(standup.id)} size="small" variant="invisible">
                Schedule
              </Button>
            }
          >
            {overview.upcoming.paused ? (
              <p className={layout.empty}>{overview.upcoming.paused_message}</p>
            ) : overview.upcoming.occurrences.length > 0 ? (
              <OccurrenceList occurrences={overview.upcoming.occurrences.slice(0, UPCOMING_LIMIT)} />
            ) : (
              <p className={layout.empty}>{overview.upcoming.empty_message}</p>
            )}
          </Panel>

          {overview.schedule_exceptions.length > 0 && (
            <Panel
              title="Schedule exceptions"
              flush
              actions={
                <Button as={RouterLink} to={paths.standupScheduleExceptions(standup.id)} size="small" variant="invisible">
                  Manage
                </Button>
              }
            >
              <ul className={layout.list} aria-label="Schedule exceptions">
                {overview.schedule_exceptions.map((exception) => {
                  const original = parseApiDate(exception.original_date);
                  const rescheduled = parseApiDate(exception.rescheduled_at);
                  return (
                    <li key={exception.id}>
                      <div className={layout.grow}>
                        <div className={layout.row}>
                          <span className={layout.title}>{original ? formatShortDate(original, true) : "—"}</span>
                          <StatusLabel tone={exception.tone}>{exception.label}</StatusLabel>
                        </div>
                        {rescheduled && <div className={layout.hint}>Moved to {formatDateTime(rescheduled)}</div>}
                        {exception.reason && <div className={layout.hint}>{exception.reason}</div>}
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Panel>
          )}

          <Panel
            title="Participants"
            actions={
              <Button as={RouterLink} to={paths.standupParticipants(standup.id)} size="small" variant="invisible">
                Manage
              </Button>
            }
          >
            {overview.sidebar_participants.length > 0 ? (
              <>
                <ul className={styles.people} aria-label="Active participants">
                  {overview.sidebar_participants.map((participant) => (
                    <li key={participant.id}>
                      <Avatar name={participant.display_name} src={participant.avatar_url} size={24} />
                      <span className={styles.personName}>{participant.display_name}</span>
                      {participant.timezone_label && <span className={layout.hint}>{participant.timezone_label}</span>}
                    </li>
                  ))}
                </ul>
                {overview.more_participants_count > 0 && <p className={layout.hint}>{overview.more_participants_count} more</p>}
              </>
            ) : (
              <p className={layout.muted}>No one has been added yet.</p>
            )}
          </Panel>
        </aside>
      </div>
    </div>
  );
}
