import { useId, useState, type FormEvent } from "react";
import { Checkbox, Dialog, FormControl, TextInput } from "@primer/react";
import type { ApiError } from "../../../api/client";
import type { ParticipantParams, RosterParticipant } from "../../../api/types/roster";
import { baseMessages, fieldMessage } from "../../../lib/fieldErrors";
import { ErrorBanner } from "../../../components";
import layout from "../../../styles/layout.module.css";

const FIELDS = ["display_name", "cached_timezone", "vacation_until", "active", "platform_user_id"];

function timeZoneNames(): string[] {
  const intl = Intl as typeof Intl & { supportedValuesOf?: (key: "timeZone") => string[] };
  try {
    return intl.supportedValuesOf?.("timeZone") ?? [];
  } catch {
    return [];
  }
}

export interface EditParticipantDialogProps {
  participant: RosterParticipant;
  saving: boolean;
  error: ApiError | null;
  onSave: (params: ParticipantParams) => void;
  onClose: () => void;
}

/** Edits a participant's name, timezone, away date and active flag (PATCH .../participants/:id). */
export function EditParticipantDialog({ participant, saving, error, onSave, onClose }: EditParticipantDialogProps) {
  const formId = useId();
  const listId = useId();
  const [displayName, setDisplayName] = useState(participant.display_name);
  const [timezone, setTimezone] = useState(participant.cached_timezone ?? "");
  const [vacationUntil, setVacationUntil] = useState(participant.vacation_until ?? "");
  const [active, setActive] = useState(participant.active);
  const [zones] = useState(timeZoneNames);

  const handleSubmit = (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    onSave({
      display_name: displayName.trim(),
      cached_timezone: timezone.trim() || null,
      vacation_until: vacationUntil || null,
      active,
    });
  };

  const nameError = fieldMessage(error, "display_name", "Name");
  const timezoneError = fieldMessage(error, "cached_timezone", "Timezone");
  const vacationError = fieldMessage(error, "vacation_until", "Away until");

  return (
    <Dialog
      title={`Edit ${participant.display_name}`}
      subtitle={<span className={layout.mono}>{participant.platform_user_id}</span>}
      onClose={() => {
        if (!saving) onClose();
      }}
      width="large"
      footerButtons={[
        { buttonType: "default", content: "Cancel", onClick: onClose, disabled: saving },
        { buttonType: "primary", content: "Save", type: "submit", form: formId, loading: saving },
      ]}
    >
      <form id={formId} className={layout.stack} onSubmit={handleSubmit} noValidate>
        <ErrorBanner title="Couldn't save this participant" error={baseMessages(error, FIELDS)} />
        <FormControl required>
          <FormControl.Label>Name</FormControl.Label>
          <TextInput name="display_name" value={displayName} onChange={(event) => setDisplayName(event.target.value)} block />
          {nameError && <FormControl.Validation variant="error">{nameError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Timezone</FormControl.Label>
          <TextInput
            name="cached_timezone"
            value={timezone}
            onChange={(event) => setTimezone(event.target.value)}
            placeholder="America/New_York"
            list={zones.length > 0 ? listId : undefined}
            autoComplete="off"
            block
          />
          {zones.length > 0 && (
            <datalist id={listId}>
              {zones.map((zone) => (
                <option key={zone} value={zone} />
              ))}
            </datalist>
          )}
          <FormControl.Caption>{participant.timezone_cache_status_description}</FormControl.Caption>
          {timezoneError && <FormControl.Validation variant="error">{timezoneError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <FormControl.Label>Away until</FormControl.Label>
          <TextInput type="date" name="vacation_until" value={vacationUntil} onChange={(event) => setVacationUntil(event.target.value)} />
          <FormControl.Caption>No prompts are sent through this date.</FormControl.Caption>
          {vacationError && <FormControl.Validation variant="error">{vacationError}</FormControl.Validation>}
        </FormControl>
        <FormControl>
          <Checkbox name="active" checked={active} onChange={(event) => setActive(event.target.checked)} />
          <FormControl.Label>Active</FormControl.Label>
          <FormControl.Caption>Inactive people stay on the list but don't get prompts.</FormControl.Caption>
        </FormControl>
      </form>
    </Dialog>
  );
}
