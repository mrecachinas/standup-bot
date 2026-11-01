import { Banner, Label, ProgressBar, VisuallyHidden } from "@primer/react";
import { ArrowDownIcon, ArrowUpIcon } from "@primer/octicons-react";
import type { InsightsParticipant, InsightsStats, Keyword, QuestionFunnel, QuestionSummary } from "../../../api/types/insights";
import { Avatar } from "../../../components/Avatar";
import { formatPercent, pluralize } from "../../../lib/format";
import { Panel, PanelEmptyText, PanelList, PanelListItem } from "./Panel";
import { progressBgForTone } from "./tone";
import styles from "./insights.module.css";

/** "↑ 5 pts" against the previous period of the same length. */
export function CompletionDelta({ stats }: { stats: Pick<InsightsStats, "completion_rate_delta" | "completion_rate_delta_direction"> }) {
  const { completion_rate_delta: delta, completion_rate_delta_direction: direction } = stats;
  if (delta === null || delta === undefined || !direction) return null;

  const variant = direction === "up" ? "success" : direction === "down" ? "danger" : "secondary";
  return (
    <Label variant={variant} title="Compared with the previous period" className={styles.delta}>
      {direction === "up" && <ArrowUpIcon size={12} aria-label="Up" />}
      {direction === "down" && <ArrowDownIcon size={12} aria-label="Down" />}
      {Math.abs(delta)} pts
    </Label>
  );
}

export function ParticipationPanel({ participants }: { participants: InsightsParticipant[] }) {
  return (
    <Panel title="Participation" description="Lowest completion first" flush>
      {participants.length > 0 ? (
        <PanelList label="Participation by person">
          {participants.map((participant) => (
            <PanelListItem
              key={participant.platform_user_id}
              leadingVisual={<Avatar name={participant.name} src={participant.avatar_url} size={24} />}
              title={
                <span className={styles.splitRow}>
                  <span className={styles.truncate}>{participant.name}</span>
                  <span className={styles.mutedSmall}>{participant.missed_label}</span>
                </span>
              }
            >
              <div className={styles.meter}>
                <ProgressBar
                  className={styles.meterBar}
                  progress={participant.completion_rate}
                  bg={progressBgForTone(participant.rate_tone)}
                  aria-label={`${participant.name} completion rate`}
                  aria-valuetext={participant.has_expected ? formatPercent(participant.completion_rate) : "No expected responses"}
                />
                <span className={styles.meterValue}>{participant.has_expected ? formatPercent(participant.completion_rate) : "—"}</span>
              </div>
            </PanelListItem>
          ))}
        </PanelList>
      ) : (
        <PanelEmptyText>No active participants.</PanelEmptyText>
      )}
    </Panel>
  );
}

export function KeywordLabels({ keywords, tone, label }: { keywords: Keyword[]; tone?: "attention"; label: string }) {
  return (
    <ul className={styles.chips} aria-label={label}>
      {keywords.map((keyword) => (
        <li key={keyword.keyword}>
          <Label variant={tone ?? "secondary"} size="large">
            {keyword.keyword}
            <span className={styles.chipCount} aria-hidden="true">
              {keyword.count}
            </span>
            <VisuallyHidden>{`, ${pluralize(keyword.count, "mention")}`}</VisuallyHidden>
          </Label>
        </li>
      ))}
    </ul>
  );
}

export function BlockersPanel({ keywords }: { keywords: Keyword[] }) {
  return (
    <Panel title="Blockers" description="Words that come up most in blocker answers">
      {keywords.length > 0 ? (
        <KeywordLabels keywords={keywords} tone="attention" label="Blocker keywords" />
      ) : (
        <p className={styles.muted}>No recurring blockers in this period.</p>
      )}
    </Panel>
  );
}

const FUNNEL_SEGMENTS = [
  { key: "answered", label: "answered", legend: "Answered", bg: "accent.emphasis" },
  { key: "skipped", label: "skipped", legend: "Skipped", bg: "accent.muted" },
  { key: "not_reached", label: "not reached", legend: "Stopped before", bg: "neutral.muted" },
] as const;

export function QuestionFunnelPanel({ funnel }: { funnel: QuestionFunnel }) {
  return (
    <Panel
      id="question-completion"
      title="Completion by question"
      description={funnel.started_label}
      actions={
        <div className={styles.legend}>
          {FUNNEL_SEGMENTS.map((segment) => (
            <span key={segment.key}>
              <i className={styles[`swatch-${segment.key}`]} aria-hidden="true" />
              {segment.legend}
            </span>
          ))}
        </div>
      }
    >
      {funnel.started === 0 ? (
        <p className={styles.muted}>No check-ins were started in this period.</p>
      ) : (
        <>
          {funnel.biggest_drop && (
            <Banner
              variant="info"
              layout="compact"
              hideTitle
              title="Biggest drop-off"
              description={`Most drop-off happens at question ${funnel.biggest_drop.position}: ${pluralize(funnel.biggest_drop.drop_off, "check-in")} ended there without an answer.`}
            />
          )}
          <ol className={styles.funnel}>
            {funnel.rows.map((row) => (
              <li key={row.position} className={styles.funnelRow}>
                <div className={styles.funnelLabel}>
                  <span className={styles.index} aria-hidden="true">
                    {row.position}
                  </span>
                  <span className={styles.truncate} title={row.question}>
                    {row.question}
                  </span>
                </div>
                <span role="group" className={styles.funnelBar} aria-label={`${row.answered} answered, ${row.skipped} skipped, ${row.not_reached} stopped before this question`}>
                  <ProgressBar>
                    {FUNNEL_SEGMENTS.map((segment) =>
                      row[segment.key] > 0 ? (
                        <ProgressBar.Item
                          key={segment.key}
                          progress={Math.round((row[segment.key] * 10000) / row.started) / 100}
                          bg={segment.bg}
                          aria-label={`${row[segment.key]} ${segment.label}`}
                        />
                      ) : null,
                    )}
                  </ProgressBar>
                </span>
                <span className={styles.funnelValue}>{formatPercent(row.answer_rate)}</span>
              </li>
            ))}
          </ol>
        </>
      )}
    </Panel>
  );
}

export function QuestionSummaries({ questions }: { questions: QuestionSummary[] }) {
  if (questions.length === 0) return null;

  return (
    <section className={styles.stack} aria-labelledby="answers-by-question">
      <h2 id="answers-by-question" className={styles.sectionTitle}>
        Answers by question
      </h2>
      <div className={styles.summaryGrid}>
        {questions.map((question) => (
          <Panel
            key={question.question}
            headingLevel="h3"
            title={question.question}
            description={`${question.answered} answered · ${question.skipped} skipped · ${formatPercent(question.answer_rate)} answer rate`}
          >
            {question.common_keywords.length > 0 && <KeywordLabels keywords={question.common_keywords} label={`Common words for “${question.question}”`} />}
            {question.latest_answers.length > 0 ? (
              <div className={styles.quotes}>
                {question.latest_answers.map((answer, index) => (
                  <blockquote key={`${answer.platform_user_id}-${index}`} className={styles.quote}>
                    <p>{answer.answer}</p>
                    <footer>
                      {answer.display_name}
                      {answer.answered_at_label && ` · ${answer.answered_at_label}`}
                    </footer>
                  </blockquote>
                ))}
              </div>
            ) : (
              <p className={styles.mutedSmall}>No answers in this period.</p>
            )}
          </Panel>
        ))}
      </div>
    </section>
  );
}
