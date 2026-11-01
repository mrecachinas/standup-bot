import { useState, type FormEvent } from "react";
import { Banner, Button, Checkbox, CheckboxGroup, FormControl, TextInput } from "@primer/react";
import { CalendarIcon, DotFillIcon } from "@primer/octicons-react";
import { patch } from "../../api/client";
import type { MemberAvailabilityParams, MemberAvailabilityPayload } from "../../api/types/member";
import { ErrorBanner, LoadingState, PageHeader } from "../../components";
import { useApi } from "../../hooks/useApi";
import { useDocumentTitle } from "../../hooks/useDocumentTitle";
import { useMutation } from "../../hooks/useMutation";
import { MemberTip } from "./components/MemberTip";
import { useClearAway } from "./components/useClearAway";
import shared from "./components/me.module.css";
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

  if (!data) {
    if (error) {
      return (
        <ErrorBanner
          error={error}
          title={error.status === 403 ? "You can't see your availability" : "Couldn't load your availability"}
          action={error.status === 403 ? undefined : <Banner.PrimaryAction onClick={reload}>Try again</Banner.PrimaryAction>}
        />
      );
    }
    return <LoadingState label="Loading your availability" />;
  }

  return (
    <div className={`${shared.page} ${shared.narrow}`}>
      <PageHeader title="Availability" description="Going on vacation or out sick? Pause your check-ins so they don't count as missed." />

      {error && <ErrorBanner error={error} title="Couldn't refresh your availability" />}

      {data.away.length > 0 && (
        <section className={shared.card} aria-labelledby="currently-away-heading">
          <div className={`${shared.cardHeader} ${styles.cardHeaderAction}`}>
            <h2 id="currently-away-heading" className={shared.cardTitle}>
              Currently away
            </h2>
            <Button size="small" onClick={() => void clearAway.run()} loading={clearAway.loading}>
              I'm back
            </Button>
          </div>
          <ul className={shared.list}>
            {data.away.map((entry) => (
              <li key={entry.participant_id} className={styles.awayItem}>
                <DotFillIcon className={styles.awayDot} aria-hidden="true" />
                <span className={styles.grow}>{entry.standup_name}</span>
                <span className={`${shared.small} ${shared.muted}`}>through {entry.vacation_until_label}</span>
              </li>
            ))}
          </ul>
        </section>
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
    <section className={shared.card} aria-labelledby="set-time-away-heading">
      <div className={shared.cardHeader}>
        <div>
          <h2 id="set-time-away-heading" className={shared.cardTitle}>
            Set time away
          </h2>
          <p className={shared.cardHint}>You won't get check-ins or reminders through this date.</p>
        </div>
      </div>
      {data.standups.length > 0 ? (
        <form onSubmit={onSubmit} noValidate>
          <div className={shared.cardBody}>
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
          </div>
          <div className={shared.cardFooter}>
            <Button type="submit" variant="primary" loading={save.loading}>
              Save
            </Button>
          </div>
        </form>
      ) : (
        <div className={shared.cardBody}>
          <p className={styles.emptyInline}>
            You aren't active in any standups right now.
          </p>
        </div>
      )}
    </section>
  );
}

function validateDate(value: string, min: string, max: string): string | undefined {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return "Choose the last day you'll be away.";
  if (value < min) return "The last day away can't be in the past.";
  if (value > max) return "You can only set time away up to a year ahead.";
  return undefined;
}
