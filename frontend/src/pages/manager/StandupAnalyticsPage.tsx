import { useParams, useSearchParams } from "react-router";
import { Banner } from "@primer/react";
import type { InsightsPayload } from "../../api/types/insights";
import { CompletionDelta, ErrorBanner, Panel, StandupHeader, StatCard, StatGrid } from "../../components";
import { RateLineChart, RunBreakdownChart, RunLegend } from "../../components/charts";
import { useForwardedQuery } from "../../hooks/useForwardedQuery";
import { formatPercent } from "../../lib/format";
import { paths } from "../../paths";
import { BlockersPanel, ParticipationPanel, QuestionFunnelPanel, QuestionSummaries } from "./insights/InsightsSections";
import { RangeToolbar } from "./insights/RangeToolbar";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";
import styles from "./insights/insights.module.css";

export function StandupAnalyticsPage() {
  const { id = "" } = useParams();
  const [, setSearchParams] = useSearchParams();
  const path = useForwardedQuery(`/api/standups/${id}/analytics`, ["start_date", "end_date", "period_days"], { view: "insights" });
  const { data, error, loading, reload, setStandup } = useStandupPage<InsightsPayload>(path, "Insights");

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Insights" />;

  const { standup, insights, csv_path: csvPath } = data;
  const { range, stats } = insights;
  const historyPath = `${paths.standupResponses(standup.id)}?${new URLSearchParams({ start_date: range.start_date, end_date: range.end_date }).toString()}`;

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="insights" onStandupChange={setStandup} />

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
            <>
              {insights.has_data ? formatPercent(stats.completion_rate) : "—"}
              {insights.has_data && <CompletionDelta value={stats.completion_rate_delta} direction={stats.completion_rate_delta_direction} />}
            </>
          }
          hint={stats.comparison_label}
        />
        <StatCard
          label="Responses"
          value={
            <>
              {stats.completed_responses}
              <span className={styles.statOf}>/ {stats.expected_responses}</span>
            </>
          }
          hint="Completed of expected"
        />
        <StatCard label="Average response time" value={stats.average_response_time_label ?? "—"} hint="From prompt to submission" />
        <StatCard label="Runs" value={stats.runs_count} hint={range.label} />
      </StatGrid>

      <Panel title="Completion over time" description="Share of expected responses completed, per run">
        <RateLineChart points={insights.completion_series} height={240} width={1000} label="Completion rate per run" />
      </Panel>

      <div className={layout.twoColumns}>
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
