import { useParams, useSearchParams } from "react-router";
import { Banner, Button } from "@primer/react";
import { InboxIcon } from "@primer/octicons-react";
import type { HistoryFilters, ResponsesHistoryPayload } from "../../api/types/roster";
import { EmptyState, ErrorBanner, StandupHeader, StatCard, StatGrid } from "../../components";
import { useForwardedQuery } from "../../hooks/useForwardedQuery";
import { formatPercent } from "../../lib/format";
import { paths } from "../../paths";
import { HistoryDaySection, HistoryFiltersCard, type FilterValues } from "./roster/ResponseHistory";
import { StandupLoadState } from "./standups/StandupLoadState";
import { useStandupPage } from "./standups/useStandupPage";
import layout from "../../styles/layout.module.css";

const FILTER_KEYS = ["start_date", "end_date", "participant", "question"] as const;

export function StandupResponsesPage() {
  const { id = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();

  const path = useForwardedQuery(`/api/standups/${id}/responses`, FILTER_KEYS, { view: "history" });
  const { data, error, loading, reload, setStandup } = useStandupPage<ResponsesHistoryPayload>(path, "Responses");

  const handleApply = (values: FilterValues) => {
    const next = new URLSearchParams();
    for (const key of FILTER_KEYS) {
      const value = values[key].trim();
      if (value) next.set(key, value);
    }
    setSearchParams(next);
  };

  if (!data) return <StandupLoadState error={error} onRetry={reload} title="Responses" />;

  const { standup, history } = data;
  const { summary } = history;
  // Prefer what's in the URL so the form matches a shared link exactly; the server fills in defaults.
  const initial: HistoryFilters = {
    start_date: searchParams.get("start_date") || history.filters.start_date,
    end_date: searchParams.get("end_date") || history.filters.end_date,
    participant: searchParams.get("participant") || history.filters.participant,
    question: searchParams.get("question") || history.filters.question,
  };
  const insightsPath = `${paths.standupAnalytics(standup.id)}?${new URLSearchParams({
    start_date: history.filters.start_date,
    end_date: history.filters.end_date,
  }).toString()}`;

  return (
    <div className={layout.page}>
      <StandupHeader standup={standup} active="responses" onStandupChange={setStandup} />

      <HistoryFiltersCard
        key={JSON.stringify(initial)}
        history={history}
        initial={initial}
        resetPath={paths.standupResponses(standup.id)}
        insightsPath={insightsPath}
        loading={loading}
        onApply={handleApply}
      />

      {error && !loading && <ErrorBanner error={error} title="Couldn't load these responses" action={<Button onClick={reload}>Try again</Button>} />}

      <section aria-label="Summary">
        <StatGrid>
          <StatCard label="Standup dates" value={summary.dates} />
          <StatCard label="Expected" value={summary.expected} />
          <StatCard
            label="Answered"
            value={summary.answered}
            tone={summary.answer_rate_tone}
            hint={summary.answer_rate !== null ? `${formatPercent(summary.answer_rate)} of expected` : "—"}
          />
          <StatCard label="Missed" value={summary.missed} />
        </StatGrid>
      </section>

      {history.range_limited && (
        <Banner variant="warning" title="Range limited" hideTitle description={`Showing the most recent ${history.max_range_days} days.`} />
      )}

      {history.days.length > 0 ? (
        <div className={layout.stack} aria-busy={loading || undefined}>
          {history.days.map((day) => (
            <HistoryDaySection key={day.date} day={day} />
          ))}
        </div>
      ) : (
        <EmptyState icon={InboxIcon} title="No runs in this range" description="Try a wider date range or clear the filters." />
      )}
    </div>
  );
}
