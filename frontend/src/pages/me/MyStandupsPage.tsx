import { Link as RouterLink } from "react-router";
import { Banner, Button, ProgressBar } from "@primer/react";
import { CalendarIcon, CheckCircleIcon, ClockIcon, CommentDiscussionIcon, PersonIcon } from "@primer/octicons-react";
import type { MemberStandupSummary, MemberStandupsPayload } from "../../api/types/member";
import { AvatarStack, EmptyState, ErrorBanner, LoadingState, PageHeader, StatCard, StatGrid, StatusLabel } from "../../components";
import { formatPercent, pluralize } from "../../lib/format";
import { progressBgForTone } from "../../lib/tone";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { MemberTip } from "./components/MemberTip";
import { useClearAway } from "./components/useClearAway";
import shared from "./components/me.module.css";
import styles from "./MyStandupsPage.module.css";

export function MyStandupsPage() {
  useDocumentTitle("My standups");
  const { data, error, reload } = useApi<MemberStandupsPayload>("/api/me/standups");
  const clearAway = useClearAway(() => reload());

  if (!data) {
    if (error) {
      return (
        <ErrorBanner
          error={error}
          title={error.status === 403 ? "You can't see these standups" : "Couldn't load your standups"}
          action={error.status === 403 ? undefined : <Banner.PrimaryAction onClick={reload}>Try again</Banner.PrimaryAction>}
        />
      );
    }
    return <LoadingState label="Loading your standups" />;
  }

  const { stats, standups, member } = data;
  const rated = stats.expected > 0;

  return (
    <div className={shared.page}>
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
  const headingId = `member-standup-${standup.id}`;
  const channel = channelLabel(summary);

  return (
    <section className={shared.card} aria-labelledby={headingId}>
      <div className={shared.cardHeader}>
        <div>
          <h2 id={headingId} className={shared.cardTitle}>
            {standup.name}
          </h2>
          {channel && <p className={shared.cardHint}>{channel}</p>}
        </div>
        <StatusLabel tone={summary.status_tone}>{summary.status_label}</StatusLabel>
      </div>
      <div className={shared.cardBody}>
        <dl className={styles.kv}>
          <dt>Schedule</dt>
          <dd>{standup.schedule_summary}</dd>
          <dt>Next check-in</dt>
          <dd>{summary.next_check_in_label ?? "—"}</dd>
          <dt>Today</dt>
          <dd>{today ? <StatusLabel tone={today.status_tone}>{today.status_label}</StatusLabel> : <span className={shared.muted}>No check-in today</span>}</dd>
          <dt>Your completion</dt>
          <dd>
            {summary.completion_rate !== null ? (
              <span className={styles.meter}>
                <ProgressBar
                  className={styles.meterBar}
                  progress={Math.min(100, Math.max(0, summary.completion_rate))}
                  bg={progressBgForTone(summary.completion_rate_tone)}
                  aria-label={`Your completion in ${standup.name}`}
                />
                <span className={styles.meterValue}>{formatPercent(summary.completion_rate)}</span>
              </span>
            ) : (
              <span className={shared.muted}>Not enough history yet</span>
            )}
          </dd>
        </dl>
        <div className={styles.teammates}>
          {teammates.length > 0 ? (
            <>
              <AvatarStack people={teammates} limit={6} />
              <span className={`${shared.small} ${shared.muted}`}>with {pluralize(teammates.length, "teammate")}</span>
            </>
          ) : (
            <span className={`${shared.small} ${shared.muted}`}>Just you so far</span>
          )}
        </div>
      </div>
      <div className={shared.cardFooter}>
        <Button as={RouterLink} to={`${paths.myResponses}?standup_id=${standup.id}`} size="small" aria-label={`My answers in ${standup.name}`}>
          My answers
        </Button>
      </div>
    </section>
  );
}
