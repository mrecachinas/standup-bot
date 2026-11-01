import { useId } from "react";
import { Link as RouterLink, useSearchParams } from "react-router";
import { Button, FormControl, SegmentedControl, Select } from "@primer/react";
import { Table } from "@primer/react/experimental";
import { CheckIcon, CommentDiscussionIcon, PlusIcon } from "@primer/octicons-react";
import type { NeedsAttentionItem, OverviewPayload, OverviewStandup, Visibility } from "../../api/types/standups";
import { EmptyState, ErrorBanner, LoadingState, PageHeader, StatCard, StatGrid } from "../../components";
import { RunBreakdownChart, RunLegend } from "../../components/charts";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { Section } from "./standups/Section";
import { StandupsTable } from "./standups/StandupsTable";
import { usePauseResume } from "./standups/usePauseResume";
import styles from "./standups/standups.module.css";

const VISIBILITIES: Visibility[] = ["all", "active", "paused"];
const DEFAULT_PERIOD_DAYS = 14;
const PERIOD_OPTIONS = [7, 14, 30, 90];

/** /manager/standups: totals, the responses-by-day chart, what needs attention, and every standup. */
export function StandupsIndexPage() {
  useDocumentTitle("Overview");
  const [searchParams, setSearchParams] = useSearchParams();
  const visibility = parseVisibility(searchParams.get("visibility"));
  const periodDays = parsePeriod(searchParams.get("period_days"));
  const query = new URLSearchParams({ visibility, period_days: String(periodDays) });
  const { data, error, loading, reload } = useApi<OverviewPayload>(`/api/overview?${query.toString()}`);
  const pauseResume = usePauseResume(() => reload());
  const tableTitleId = useId();

  const updateFilters = (next: { visibility?: Visibility; period_days?: number }) => {
    const params = new URLSearchParams(searchParams);
    if (next.visibility) params.set("visibility", next.visibility);
    if (next.period_days) params.set("period_days", String(next.period_days));
    setSearchParams(params);
  };

  const newStandupButton = (
    <Button as={RouterLink} to={paths.newStandup} variant="primary" leadingVisual={PlusIcon}>
      New standup
    </Button>
  );

  const periodOptions = PERIOD_OPTIONS.includes(periodDays) ? PERIOD_OPTIONS : [...PERIOD_OPTIONS, periodDays].sort((a, b) => a - b);

  return (
    <div className={styles.page}>
      <PageHeader
        title="Overview"
        description={data?.subtitle ?? `How your standups are doing over the last ${periodDays} days.`}
        actions={
          <div className={styles.filters}>
            {data && !data.empty && (
              <FormControl>
                <FormControl.Label visuallyHidden>Period</FormControl.Label>
                <Select value={String(periodDays)} onChange={(event) => updateFilters({ period_days: Number(event.target.value) })}>
                  {periodOptions.map((days) => (
                    <Select.Option key={days} value={String(days)}>
                      Last {days} days
                    </Select.Option>
                  ))}
                </Select>
              </FormControl>
            )}
            {newStandupButton}
          </div>
        }
      />

      <ErrorBanner error={pauseResume.error} onDismiss={pauseResume.reset} title="Couldn't change the standup" />

      {!data && loading && <LoadingState label="Loading standups…" />}
      {!data && error && <ErrorBanner error={error} title="Couldn't load your standups" action={<Button onClick={reload}>Try again</Button>} />}

      {data?.empty && (
        <EmptyState
          icon={CommentDiscussionIcon}
          title="Create your first standup"
          description="Pick a schedule and a few questions. Standup Bot will DM your team in Slack or Microsoft Teams and collect the answers."
          action={newStandupButton}
          secondaryAction={
            <Button as={RouterLink} to={paths.integrations}>
              Connect a chat app
            </Button>
          }
        />
      )}

      {data && !data.empty && (
        <>
          {error && <ErrorBanner error={error} title="Couldn't refresh your standups" action={<Button onClick={reload}>Try again</Button>} />}
          <StatGrid>
            <StatCard label="Active standups" value={data.stats.active_count} hint={data.stats.paused_label} />
            <StatCard label="People" value={data.stats.people_count} hint={data.stats.people_label} />
            <StatCard
              label="Completion rate"
              value={data.stats.completion_rate_label}
              hint={data.stats.completion_sub_label}
              tone={data.stats.completion_tone}
            />
            <StatCard label="Needs attention" value={data.stats.needs_attention_count} hint={data.stats.needs_attention_label} />
          </StatGrid>

          <div className={styles.mainAside}>
            <Section title="Responses by day" hint="All standups combined" actions={<RunLegend pending={data.daily_has_pending} />}>
              <RunBreakdownChart runs={data.daily_totals} height={220} label="Responses by day across all standups" />
            </Section>
            <NeedsAttention
              items={data.needs_attention}
              emptyMessage={data.needs_attention_empty_message}
              busy={pauseResume.loading}
              onResume={(item) => void pauseResume.run(item.standup_id, false)}
            />
          </div>

          <Table.Container>
            <Table.Title as="h2" id={tableTitleId}>
              Standups
            </Table.Title>
            <Table.Actions>
              <SegmentedControl aria-label="Filter standups" size="small" onChange={(index) => updateFilters({ visibility: VISIBILITIES[index] })}>
                {data.visibility_options.map((option) => (
                  <SegmentedControl.Button key={option.value} selected={option.value === visibility}>
                    {option.label}
                  </SegmentedControl.Button>
                ))}
              </SegmentedControl>
            </Table.Actions>
            {data.standups.length > 0 ? (
              <StandupsTable
                standups={data.standups}
                labelledBy={tableTitleId}
                onPauseResume={(standup: OverviewStandup) => void pauseResume.run(standup.id, standup.active)}
              />
            ) : (
              <p className={`${styles.card} ${styles.inlineEmpty} ${styles.tableEmpty}`}>{data.empty_list_message}</p>
            )}
          </Table.Container>
        </>
      )}
    </div>
  );
}

function NeedsAttention({
  items,
  emptyMessage,
  busy,
  onResume,
}: {
  items: NeedsAttentionItem[];
  emptyMessage: string;
  busy: boolean;
  onResume: (item: NeedsAttentionItem) => void;
}) {
  return (
    <Section title="Needs attention" flush>
      {items.length > 0 ? (
        <ul className={styles.list}>
          {items.map((item) => (
            <li key={item.standup_id}>
              <span className={`${styles.dot} ${styles[`dot-${item.tone ?? "warning"}`]}`} aria-hidden="true" />
              <div className={styles.grow}>
                <RouterLink to={paths.standup(item.standup_id)} className={styles.title}>
                  {item.name}
                </RouterLink>
                <div className={styles.sub}>{item.reason}</div>
              </div>
              {!item.active && (
                <Button size="small" disabled={busy} onClick={() => onResume(item)} aria-label={`Resume ${item.name}`}>
                  Resume
                </Button>
              )}
            </li>
          ))}
        </ul>
      ) : (
        <EmptyState icon={CheckIcon} title="All clear" description={emptyMessage} border={false} size="small" headingLevel="h3" />
      )}
    </Section>
  );
}

function parseVisibility(value: string | null): Visibility {
  return VISIBILITIES.find((option) => option === value) ?? "all";
}

function parsePeriod(value: string | null): number {
  const days = Number(value);
  return Number.isInteger(days) && days >= 1 && days <= 90 ? days : DEFAULT_PERIOD_DAYS;
}
