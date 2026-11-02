import { Link as RouterLink } from "react-router";
import { Banner, Button } from "@primer/react";
import { CalendarIcon, CheckCircleIcon, ClockIcon, CommentDiscussionIcon, PersonIcon } from "@primer/octicons-react";
import type { MemberStandupSummary, MemberStandupsPayload } from "../../api/types/member";
import { AvatarStack, EmptyState, ErrorBanner, Meter, PageHeader, Panel, StatCard, StatGrid, StatusLabel } from "../../components";
import { formatPercent, pluralize } from "../../lib/format";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { MemberLoadState } from "./components/MemberLoadState";
import { MemberTip } from "./components/MemberTip";
import { useClearAway } from "./components/useClearAway";
import layout from "../../styles/layout.module.css";
import styles from "./MyStandupsPage.module.css";

export function MyStandupsPage() {
  useDocumentTitle("My standups");
  const { data, error, reload } = useApi<MemberStandupsPayload>("/api/me/standups");
  const clearAway = useClearAway(() => reload());

  if (!data) return <MemberLoadState error={error} onRetry={reload} what="your standups" />;

  const { stats, standups, member } = data;
  const rated = stats.expected > 0;

  return (
    <div className={layout.page}>
      <PageHeader
        title="My standups"
        description={`Your check-ins across ${pluralize(standups.length, "standup")}. Answer them in your ${member.platform_label} DMs.`}
        actions={
          <Button as={RouterLink} to={paths.availability} leadingVisual={CalendarIcon}>
            Set time away
          </Button>
        }
      />

      {error && <ErrorBanner error={error} title="Couldn't refresh your standups" />}

      {data.away_until && (
        <Banner
          variant="info"
          title="You're away"
          hideTitle
          description={
            <>
              You're away through <strong>{data.away_until_label}</strong>. You won't get check-ins until then.
            </>
          }
          primaryAction={
            <Banner.PrimaryAction onClick={() => void clearAway.run()} loading={clearAway.loading}>
              I'm back
            </Banner.PrimaryAction>
          }
        />
      )}

      <StatGrid>
        <StatCard label="Standups" icon={CommentDiscussionIcon} value={stats.standups_count} hint={`${stats.active_count} active`} />
        <StatCard
          label={`Your completion · ${stats.period_days} days`}
          icon={CheckCircleIcon}
          value={rated ? formatPercent(stats.completion_rate) : "—"}
          hint={`${stats.completed} of ${stats.expected} check-ins`}
        />
        <StatCard
          label="Next check-in"
          icon={ClockIcon}
          value={stats.next_check_in ? stats.next_check_in.date_label : "—"}
          hint={stats.next_check_in ? `${stats.next_check_in.time_label} · ${stats.next_check_in.standup_name}` : "Nothing scheduled"}
        />
        <StatCard label="Status" icon={PersonIcon} value={stats.status_label} hint={stats.status_detail} />
      </StatGrid>

      {standups.length > 0 ? (
        <div className={styles.grid}>
          {standups.map((summary) => (
            <StandupCard key={summary.standup.id} summary={summary} />
          ))}
        </div>
      ) : (
        <EmptyState
          icon={CommentDiscussionIcon}
          title="You're not in any standups yet"
          description={`When a manager adds you to a standup, it shows up here and your check-ins arrive in ${member.platform_label}.`}
        />
      )}

      <MemberTip>Tip: in {member.platform_label},</MemberTip>
    </div>
  );
}

function channelLabel(summary: MemberStandupSummary): string | null {
  const reference = summary.standup.channel_reference ?? summary.standup.platform_channel;
  if (!reference) return null;
  return reference.replace(/^#+/, "#");
}

function StandupCard({ summary }: { summary: MemberStandupSummary }) {
  const { standup, today, teammates } = summary;

  return (
    <Panel
      title={standup.name}
      description={channelLabel(summary)}
      actions={<StatusLabel tone={summary.status_tone}>{summary.status_label}</StatusLabel>}
      footer={
        <Button as={RouterLink} to={`${paths.myResponses}?standup_id=${standup.id}`} size="small" aria-label={`My answers in ${standup.name}`}>
          My answers
        </Button>
      }
    >
      <dl className={styles.kv}>
        <dt>Schedule</dt>
        <dd>{standup.schedule_summary}</dd>
        <dt>Next check-in</dt>
        <dd>{summary.next_check_in_label ?? "—"}</dd>
        <dt>Today</dt>
        <dd>{today ? <StatusLabel tone={today.status_tone}>{today.status_label}</StatusLabel> : <span className={layout.muted}>No check-in today</span>}</dd>
        <dt>Your completion</dt>
        <dd>
          {summary.completion_rate !== null ? (
            <Meter className={styles.meter} value={summary.completion_rate} tone={summary.completion_rate_tone} label={`Your completion in ${standup.name}`}>
              {formatPercent(summary.completion_rate)}
            </Meter>
          ) : (
            <span className={layout.muted}>Not enough history yet</span>
          )}
        </dd>
      </dl>
      <div className={styles.teammates}>
        {teammates.length > 0 ? (
          <>
            <AvatarStack people={teammates} limit={6} />
            <span className={layout.hint}>with {pluralize(teammates.length, "teammate")}</span>
          </>
        ) : (
          <span className={layout.hint}>Just you so far</span>
        )}
      </div>
    </Panel>
  );
}
