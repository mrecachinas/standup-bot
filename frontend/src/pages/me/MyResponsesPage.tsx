import { useSearchParams } from "react-router";
import { SegmentedControl } from "@primer/react";
import { InboxIcon } from "@primer/octicons-react";
import type { MemberResponse, MemberResponsesPayload } from "../../api/types/member";
import { DateTile, EmptyState, ErrorBanner, LoadingState, PageHeader, Panel, StatusLabel } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { MemberLoadState } from "./components/MemberLoadState";
import layout from "../../styles/layout.module.css";
import styles from "./MyResponsesPage.module.css";

export function MyResponsesPage() {
  useDocumentTitle("My responses");
  const [searchParams, setSearchParams] = useSearchParams();
  const standupId = searchParams.get("standup_id") ?? "";
  const path = standupId ? `/api/me/responses?standup_id=${encodeURIComponent(standupId)}` : "/api/me/responses";
  const { data, error, loading, reload } = useApi<MemberResponsesPayload>(path);

  if (!data) return <MemberLoadState error={error} onRetry={reload} what="your responses" />;

  const platformLabel = data.member.platform_label;
  const selected = data.standups.find((standup) => String(standup.id) === standupId) ?? null;
  const selectedName = selected?.name ?? data.standup?.name;

  const selectStandup = (id: number | null) => {
    setSearchParams(id === null ? {} : { standup_id: String(id) });
  };

  return (
    <div className={layout.page}>
      <PageHeader title="My responses" description={`Your most recent check-ins${selectedName ? ` in ${selectedName}` : ""}.`}>
        {data.standups.length > 1 && (
          <SegmentedControl
            aria-label="Filter by standup"
            variant={{ narrow: "dropdown", regular: "default" }}
            onChange={(index) => selectStandup(index === 0 ? null : data.standups[index - 1].id)}
          >
            <SegmentedControl.Button selected={selected === null}>All</SegmentedControl.Button>
            {data.standups.map((standup) => (
              <SegmentedControl.Button key={standup.id} selected={selected?.id === standup.id}>
                {standup.name}
              </SegmentedControl.Button>
            ))}
          </SegmentedControl>
        )}
      </PageHeader>

      {error && <ErrorBanner error={error} title="Couldn't load your responses" />}

      {loading ? (
        <LoadingState label="Loading your responses" />
      ) : data.responses.length > 0 ? (
        <>
          <Panel flush label="Check-ins">
            <ul className={layout.list}>
              {data.responses.map((response) => (
                <ResponseItem key={response.id} response={response} platformLabel={platformLabel} />
              ))}
            </ul>
          </Panel>
          {data.limited && <p className={layout.hint}>Showing your {data.limit} most recent check-ins.</p>}
        </>
      ) : (
        <EmptyState icon={InboxIcon} title="No check-ins yet" description="Your answers will show up here after your first standup." />
      )}
    </div>
  );
}

function ResponseItem({ response, platformLabel }: { response: MemberResponse; platformLabel: string }) {
  return (
    <li className={layout.top} id={`response_${response.id}`}>
      <DateTile date={response.date} />
      <div className={styles.body}>
        <div className={layout.row}>
          <span className={layout.title}>{response.standup_name}</span>
          <span className={layout.hint}>{response.date_label}</span>
          <StatusLabel tone={response.status_tone}>{response.status_label}</StatusLabel>
        </div>
        {response.answers.length > 0 ? (
          <dl className={styles.answers}>
            {response.answers.map((answer, index) => (
              <div key={index}>
                <dt className={styles.question}>{answer.question}</dt>
                <dd className={answer.answer ? styles.answer : styles.noAnswer}>{answer.answer ?? "No answer"}</dd>
              </div>
            ))}
          </dl>
        ) : response.status === "pending" ? (
          <p className={layout.hint}>Waiting for your answers in {platformLabel}.</p>
        ) : (
          <p className={layout.hint}>No answers recorded.</p>
        )}
      </div>
    </li>
  );
}
