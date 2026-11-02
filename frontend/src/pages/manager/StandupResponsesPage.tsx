import { useParams, useSearchParams } from "react-router";
import { Banner, Button } from "@primer/react";
import { InboxIcon } from "@primer/octicons-react";
import type { Standup } from "../../api/types";
import type { HistoryFilters, ResponsesHistoryPayload } from "../../api/types/roster";
import { EmptyState, ErrorBanner, formatPercent, LoadingState, pluralize, StandupHeader, StatCard, StatGrid } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { paths } from "../../paths";
import { HistoryDaySection, HistoryFiltersCard, type FilterValues } from "./roster/ResponseHistory";
import { StandupLoadError } from "./roster/StandupLoadError";
import { usePauseResume } from "./roster/usePauseResume";
import styles from "./roster/roster.module.css";

const FILTER_KEYS = ["start_date", "end_date", "participant", "question"] as const;

export function StandupResponsesPage() {
  const { id = "" } = useParams();
  const [searchParams, setSearchParams] = useSearchParams();

  // Only the filter params go to the API, in a stable order.
  const query = new URLSearchParams({ view: "history" });
  for (const key of FILTER_KEYS) {
    const value = searchParams.get(key);
    if (value) query.set(key, value);
  }
  const { data, error, loading, reload, setData } = useApi<ResponsesHistoryPayload>(`/api/standups/${id}/responses?${query.toString()}`);
  useDocumentTitle(data ? `Responses · ${data.standup.name}` : "Responses");

  const pauseResume = usePauseResume(data?.standup, (standup: Standup) => setData((current) => ({ ...(current as ResponsesHistoryPayload), standup })));

  const handleApply = (values: FilterValues) => {
    const next = new URLSearchParams();
    for (const key of FILTER_KEYS) {
      const value = values[key].trim();
      if (value) next.set(key, value);
    }
    setSearchParams(next);
  };

  if (!data) {
    if (error) return <StandupLoadError error={error} title="Responses" onRetry={reload} />;
    return <LoadingState label="Loading responses…" />;
  }

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
    <div className={styles.page}>
      <StandupHeader standup={standup} active="responses" onPauseResume={pauseResume.toggle} pauseResumeBusy={pauseResume.busy} />

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
          <StatCard label="Expected" value={summary.expected} hint={`Across ${pluralize(summary.dates, "standup date")}`} />
          <StatCard
            label="Answered"
            value={summary.answered}
            tone={summary.answer_rate_tone}
            hint={summary.answer_rate !== null ? `${formatPercent(summary.answer_rate)} of expected` : "—"}
          />
          <StatCard label="Skipped" value={summary.skipped} hint="Chose to skip" />
          <StatCard label="Missed" value={summary.missed} hint={summary.pending > 0 ? `${summary.pending} still waiting to answer` : "No answer"} />
        </StatGrid>
      </section>

      {history.range_limited && (
        <Banner variant="warning" title="Range limited" hideTitle description={`Showing the most recent ${history.max_range_days} days.`} />
      )}

      {history.days.length > 0 ? (
        <div className={styles.stack} aria-busy={loading || undefined}>
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
