import { useParams, useSearchParams } from "react-router";
import { Banner } from "@primer/react";
import type { InsightsPayload } from "../../api/types/insights";
import { ErrorBanner, LoadingState, StandupHeader, StatCard, StatGrid } from "../../components";
import { formatPercent } from "../../lib/format";
import { RateLineChart, RunBreakdownChart, RunLegend } from "../../components/charts";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { BlockersPanel, CompletionDelta, ParticipationPanel, QuestionFunnelPanel, QuestionSummaries } from "./insights/InsightsSections";
import { PageLoadError } from "./insights/PageLoadError";
import { Panel } from "./insights/Panel";
import { RangeToolbar } from "./insights/RangeToolbar";
import { useStandupPauseResume } from "./insights/useStandupPauseResume";
import styles from "./insights/insights.module.css";

const RANGE_PARAMS = ["start_date", "end_date", "period_days"] as const;

export function StandupAnalyticsPage() {
  const { id = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();
  const query = new URLSearchParams({ view: "insights" });
  for (const key of RANGE_PARAMS) {
    const value = searchParams.get(key);
    if (value) query.set(key, value);
  }

  const { data, error, loading, reload, setData } = useApi<InsightsPayload>(`/api/standups/${id}/analytics?${query.toString()}`);
  const pauseResume = useStandupPauseResume(data?.standup, (standup) => setData((current) => ({ ...(current as InsightsPayload), standup })));
  useDocumentTitle(data ? `Insights · ${data.standup.name}` : "Insights");

  if (!data) {
    if (error) return <PageLoadError error={error} onRetry={reload} />;
    return <LoadingState label="Loading insights…" />;
  }

  const { standup, insights, csv_path: csvPath } = data;
  const { range, stats } = insights;
  const historyPath = `${paths.standupResponses(standup.id)}?${new URLSearchParams({ start_date: range.start_date, end_date: range.end_date }).toString()}`;

  return (
    <div className={styles.page}>
      <StandupHeader standup={standup} active="insights" onPauseResume={pauseResume.onPauseResume} pauseResumeBusy={pauseResume.busy} />

      <RangeToolbar
        range={range}
        csvPath={csvPath}
        historyPath={historyPath}
        loading={loading}
        onChange={(next) => setSearchParams({ start_date: next.start_date, end_date: next.end_date })}
      />

      <ErrorBanner error={error} title="Couldn't update insights" />

      {range.limited && <Banner variant="warning" title="Range limited" hideTitle description={`Showing the most recent ${range.max_days} days.`} />}

      <StatGrid>
        <StatCard
          label="Completion rate"
          value={
            <span className={styles.statValue}>
              {insights.has_data ? formatPercent(stats.completion_rate) : "—"}
              {insights.has_data && <CompletionDelta stats={stats} />}
            </span>
          }
          hint={stats.comparison_label}
        />
        <StatCard
          label="Responses"
          value={
            <span className={styles.statValue}>
              {stats.completed_responses}
              <span className={styles.statOf}>/ {stats.expected_responses}</span>
            </span>
          }
          hint="Completed of expected"
        />
        <StatCard label="Average response time" value={stats.average_response_time_label ?? "—"} hint="From prompt to submission" />
        <StatCard label="Runs" value={stats.runs_count} hint={range.label} />
      </StatGrid>

      <Panel title="Completion over time" description="Share of expected responses completed, per run">
        <RateLineChart points={insights.completion_series} height={240} width={1000} label="Completion rate per run" />
      </Panel>

      <div className={styles.twoColumns}>
        <Panel title="Responses per run" description="What happened to each prompt" actions={<RunLegend pending={insights.runs_have_pending} />}>
          <RunBreakdownChart runs={insights.runs} height={200} width={480} />
        </Panel>
        <ParticipationPanel participants={insights.participants} />
      </div>

      <BlockersPanel keywords={insights.blocker_keywords} />
      <QuestionFunnelPanel funnel={insights.question_funnel} />
      <QuestionSummaries questions={insights.question_summaries} />
    </div>
  );
}
