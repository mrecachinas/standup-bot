import { useState, type FormEvent } from "react";
import { Link as RouterLink } from "react-router";
import { Button, FormControl, Select, TextInput } from "@primer/react";
import { GraphIcon } from "@primer/octicons-react";
import type { HistoryDay, HistoryEntry, HistoryFilters, ResponseHistory } from "../../../api/types/roster";
import { Avatar, DateTile, Meter, Panel, StatusLabel } from "../../../components";
import { formatPercent } from "../../../lib/format";
import layout from "../../../styles/layout.module.css";
import styles from "./roster.module.css";

export interface FilterValues {
  start_date: string;
  end_date: string;
  participant: string;
  question: string;
}

export interface HistoryFiltersCardProps {
  history: ResponseHistory;
  /** Filter values to start with (the URL's, falling back to the server's normalised ones). */
  initial: HistoryFilters;
  resetPath: string;
  insightsPath: string;
  loading: boolean;
  onApply: (values: FilterValues) => void;
}

export function HistoryFiltersCard({ history, initial, resetPath, insightsPath, loading, onApply }: HistoryFiltersCardProps) {
  const [values, setValues] = useState<FilterValues>({
    start_date: initial.start_date,
    end_date: initial.end_date,
    participant: initial.participant ?? "",
    question: initial.question ?? "",
  });
  const set = (key: keyof FilterValues) => (event: { target: { value: string } }) => setValues((current) => ({ ...current, [key]: event.target.value }));

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    onApply(values);
  };

  const participantOptions = history.participant_options;
  const questionOptions = history.question_options;
  const hasSelectedParticipant = !values.participant || participantOptions.some((option) => option.platform_user_id === values.participant);
  const hasSelectedQuestion = !values.question || questionOptions.includes(values.question);

  return (
    <Panel
      footer={
        <>
          <Button as={RouterLink} to={resetPath} size="small" variant="invisible">
            Reset filters
          </Button>
          <Button as={RouterLink} to={insightsPath} size="small" leadingVisual={GraphIcon}>
            View insights
          </Button>
        </>
      }
    >
      <form className={styles.formGrid} onSubmit={handleSubmit} role="search" aria-label="Response filters">
        <FormControl>
          <FormControl.Label>From</FormControl.Label>
          <TextInput type="date" name="start_date" value={values.start_date} onChange={set("start_date")} block />
        </FormControl>
        <FormControl>
          <FormControl.Label>To</FormControl.Label>
          <TextInput type="date" name="end_date" value={values.end_date} onChange={set("end_date")} block />
        </FormControl>
        <FormControl>
          <FormControl.Label>Person</FormControl.Label>
          <Select name="participant" value={values.participant} onChange={set("participant")} block>
            <Select.Option value="">Everyone</Select.Option>
            {!hasSelectedParticipant && <Select.Option value={values.participant}>{values.participant}</Select.Option>}
            {participantOptions.map((option) => (
              <Select.Option key={option.platform_user_id} value={option.platform_user_id}>
                {option.label}
              </Select.Option>
            ))}
          </Select>
        </FormControl>
        <FormControl>
          <FormControl.Label>Question</FormControl.Label>
          <Select name="question" value={values.question} onChange={set("question")} block>
            <Select.Option value="">All questions</Select.Option>
            {!hasSelectedQuestion && <Select.Option value={values.question}>{values.question}</Select.Option>}
            {questionOptions.map((question) => (
              <Select.Option key={question} value={question}>
                {question}
              </Select.Option>
            ))}
          </Select>
        </FormControl>
        <div>
          <Button type="submit" loading={loading}>
            Apply
          </Button>
        </div>
      </form>
    </Panel>
  );
}

export function HistoryDaySection({ day }: { day: HistoryDay }) {
  return (
    <Panel
      id={`standup-history-${day.date}`}
      headingId={`standup-history-${day.date}-heading`}
      title={day.date_label}
      description={`${day.answered_count} answered · ${day.missed_count} missed · ${day.expected_count} expected`}
      leadingVisual={<DateTile date={day.date} />}
      actions={
        <Meter className={styles.dayMeter} value={day.answer_rate} tone={day.answer_rate_tone} label={`${formatPercent(day.answer_rate)} answered on ${day.date_label}`}>
          {formatPercent(day.answer_rate)}
        </Meter>
      }
      flush
    >
      <ul className={layout.list}>
        {day.entries.map((entry) => (
          <HistoryEntryItem key={entry.platform_user_id} date={day.date} entry={entry} />
        ))}
      </ul>
    </Panel>
  );
}

function HistoryEntryItem({ date, entry }: { date: string; entry: HistoryEntry }) {
  const name = entry.display_name || entry.platform_user_id;
  return (
    <li id={`standup-history-${date}-${slug(entry.platform_user_id)}`} className={layout.top}>
      <Avatar name={name} src={entry.avatar_url} />
      <div className={`${layout.grow} ${styles.entry}`}>
        <div className={layout.row}>
          <span className={layout.title}>{entry.display_name}</span>
          <span className={`${layout.hint} ${layout.mono}`}>{entry.platform_user_id}</span>
          <StatusLabel tone={entry.status_tone}>{entry.status_label}</StatusLabel>
        </div>

        {entry.answers.length > 0 ? (
          <div className={styles.answers}>
            {entry.answers.map((answer, index) => (
              <div key={`${answer.question}-${index}`} className={styles.answer}>
                <span className={styles.answerQuestion}>{answer.question}</span>
                <span className={answer.text ? styles.answerText : `${styles.answerText} ${layout.muted}`}>{answer.display_text}</span>
                {answer.timestamp && answer.answered_at_label && <span className={layout.hint}>Answered at {answer.answered_at_label}</span>}
              </div>
            ))}
          </div>
        ) : (
          entry.empty_message && <p className={layout.hint}>{entry.empty_message}</p>
        )}

        {entry.response_id !== null && (
          <p className={layout.hint}>
            Submitted {entry.submitted_at_label ?? "Unknown"} · Last updated {entry.updated_at_label ?? "Unknown"}
            {entry.updated_after_create && " · Updated after submission"}
          </p>
        )}
      </div>
    </li>
  );
}

function slug(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}
