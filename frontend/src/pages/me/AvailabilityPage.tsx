import { useId, useState, type FormEvent } from "react";
import { Button, Checkbox, CheckboxGroup, FormControl, TextInput } from "@primer/react";
import { CalendarIcon, DotFillIcon } from "@primer/octicons-react";
import { patch } from "../../api/client";
import type { MemberAvailabilityParams, MemberAvailabilityPayload } from "../../api/types/member";
import { ErrorBanner, PageHeader, Panel, PanelBody } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useMutation } from "../../hooks/useMutation";
import { MemberLoadState } from "./components/MemberLoadState";
import { MemberTip } from "./components/MemberTip";
import { useClearAway } from "./components/useClearAway";
import layout from "../../styles/layout.module.css";
import styles from "./AvailabilityPage.module.css";

const PATH = "/api/me/availability";

export function AvailabilityPage() {
  useDocumentTitle("Availability");
  const { data, error, reload, setData } = useApi<MemberAvailabilityPayload>(PATH);
  // Bumped after each save/clear so the form resets to the server's state.
  const [formVersion, setFormVersion] = useState(0);
  const clearAway = useClearAway((result) => {
    setData(result);
    setFormVersion((version) => version + 1);
  });

  if (!data) return <MemberLoadState error={error} onRetry={reload} what="your availability" />;

  return (
    <div className={`${layout.page} ${layout.narrow}`}>
      <PageHeader title="Availability" description="Going on vacation or out sick? Pause your check-ins so they don't count as missed." />

      {error && <ErrorBanner error={error} title="Couldn't refresh your availability" />}

      {data.away.length > 0 && (
        <Panel
          title="Currently away"
          flush
          actions={
            <Button size="small" onClick={() => void clearAway.run()} loading={clearAway.loading}>
              I'm back
            </Button>
          }
        >
          <ul className={layout.list}>
            {data.away.map((entry) => (
              <li key={entry.participant_id}>
                <DotFillIcon className={styles.awayDot} aria-hidden="true" />
                <span className={layout.grow}>{entry.standup_name}</span>
                <span className={layout.hint}>through {entry.vacation_until_label}</span>
              </li>
            ))}
          </ul>
        </Panel>
      )}

      <AvailabilityForm
        key={formVersion}
        data={data}
        onSaved={(result) => {
          setData(result);
          setFormVersion((version) => version + 1);
        }}
      />

      <MemberTip>You can also</MemberTip>
    </div>
  );
}

function AvailabilityForm({ data, onSaved }: { data: MemberAvailabilityPayload; onSaved: (result: MemberAvailabilityPayload) => void }) {
  const formId = useId();
  const [awayUntil, setAwayUntil] = useState("");
  const [selected, setSelected] = useState<number[]>(() => data.standups.filter((standup) => standup.selected).map((standup) => standup.standup_id));
  const [submitted, setSubmitted] = useState(false);
  const save = useMutation((params: MemberAvailabilityParams) => patch<MemberAvailabilityPayload>(PATH, params), { onSuccess: onSaved });

  const dateError = submitted ? validateDate(awayUntil, data.min_date, data.max_date) : undefined;
  const standupsError = submitted && selected.length === 0 ? "Choose at least one standup." : undefined;

  const toggle = (standupId: number, checked: boolean) => {
    setSelected((current) => (checked ? [...current.filter((id) => id !== standupId), standupId] : current.filter((id) => id !== standupId)));
  };

  const onSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitted(true);
    if (validateDate(awayUntil, data.min_date, data.max_date) || selected.length === 0) return;
    const order = data.standups.map((standup) => standup.standup_id);
    void save.run({ away_until: awayUntil, standup_ids: order.filter((id) => selected.includes(id)) });
  };

  return (
    <Panel
      title="Set time away"
      description="You won't get check-ins or reminders through this date."
      flush
      footer={
        data.standups.length > 0 && (
          <Button type="submit" form={formId} variant="primary" loading={save.loading}>
            Save
          </Button>
        )
      }
    >
      {data.standups.length > 0 ? (
        <form id={formId} onSubmit={onSubmit} noValidate>
          <PanelBody>
            {save.error && <ErrorBanner error={save.error} title="Couldn't set your time away" onDismiss={save.reset} />}
            <FormControl required>
              <FormControl.Label>Last day away</FormControl.Label>
              <TextInput
                type="date"
                className={styles.dateInput}
                leadingVisual={CalendarIcon}
                value={awayUntil}
                min={data.min_date}
                max={data.max_date}
                onChange={(event) => setAwayUntil(event.target.value)}
                validationStatus={dateError ? "error" : undefined}
              />
              {dateError && <FormControl.Validation variant="error">{dateError}</FormControl.Validation>}
            </FormControl>
            <CheckboxGroup required>
              <CheckboxGroup.Label>Standups</CheckboxGroup.Label>
              {data.standups.map((standup) => (
                <FormControl key={standup.standup_id}>
                  <Checkbox
                    value={String(standup.standup_id)}
                    checked={selected.includes(standup.standup_id)}
                    onChange={(event) => toggle(standup.standup_id, event.target.checked)}
                  />
                  <FormControl.Label>{standup.standup_name}</FormControl.Label>
                </FormControl>
              ))}
              {standupsError && <CheckboxGroup.Validation variant="error">{standupsError}</CheckboxGroup.Validation>}
            </CheckboxGroup>
          </PanelBody>
        </form>
      ) : (
        <p className={layout.empty}>You aren't active in any standups right now.</p>
      )}
    </Panel>
  );
}

function validateDate(value: string, min: string, max: string): string | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return "Choose the last day you'll be away.";
  if (value < min) return "The last day away can't be in the past.";
  if (value > max) return "You can only set time away up to a year ahead.";
  return undefined;
}
