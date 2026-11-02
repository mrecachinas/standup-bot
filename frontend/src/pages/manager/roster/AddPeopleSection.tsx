import { useState, type FormEvent, type ReactNode } from "react";
import { Button, Checkbox, FormControl, Textarea, TextInput } from "@primer/react";
import { ChevronRightIcon, SyncIcon, UploadIcon } from "@primer/octicons-react";
import { ApiError, post } from "../../../api/client";
import type { ImportResult, ImportSummary, ParticipantMutationResult, ParticipantsConsole } from "../../../api/types/roster";
import { ErrorBanner, Panel, PanelBody } from "../../../components";
import { pluralize } from "../../../lib/format";
import { useMutation } from "../../../hooks/useMutation";
import { baseMessages, fieldMessage } from "../../../lib/fieldErrors";
import layout from "../../../styles/layout.module.css";
import styles from "./roster.module.css";

export interface AddPeopleSectionProps {
  standupId: number;
  roster: ParticipantsConsole;
  /** Reload the roster after something changed. */
  onChanged: () => void;
}

const ADD_FIELDS = ["platform_user_id"];

/** "Add people": add one person, import a list, or sync from a channel. */
export function AddPeopleSection({ standupId, roster, onChanged }: AddPeopleSectionProps) {
  const { platform, sync_defaults: syncDefaults } = roster;
  const copy = platform.copy;
  const base = `/api/standups/${standupId}/participants`;

  const [handle, setHandle] = useState("");
  const add = useMutation(
    (identifier: string) => post<ParticipantMutationResult>(base, { participant: { platform_user_id: identifier, active: true }, lookup: true }),
    {
      onSuccess: () => {
        setHandle("");
        onChanged();
      },
    },
  );

  const [importOpen, setImportOpen] = useState(false);
  const [importText, setImportText] = useState("");
  const bulkImport = useMutation((text: string) => reloadOnPartialChange(post<ImportResult>(`${base}/bulk_import`, { participants_text: text }), onChanged), {
    onSuccess: () => {
      setImportText("");
      onChanged();
    },
  });

  const [syncOpen, setSyncOpen] = useState(false);
  const [channel, setChannel] = useState(syncDefaults.channel ?? "");
  const [deactivateMissing, setDeactivateMissing] = useState(syncDefaults.deactivate_missing);
  const sync = useMutation(
    (args: { channel: string; deactivate_missing: boolean }) => reloadOnPartialChange(post<ImportResult>(`${base}/sync`, args), onChanged),
    { onSuccess: () => onChanged() },
  );

  const handleAdd = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!handle.trim()) return;
    await add.run(handle.trim());
  };

  const handleImport = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    await bulkImport.run(importText);
  };

  const handleSync = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    await sync.run({ channel: channel.trim(), deactivate_missing: deactivateMissing });
  };

  const addErrors = baseMessages(add.error, ADD_FIELDS);
  const handleError = fieldMessage(add.error, "platform_user_id", `${platform.label} user`);

  return (
    <>
      <ErrorBanner error={addErrors} title={`${pluralize(addErrors.length, "error")} prevented saving this participant`} onDismiss={add.reset} />
      <ErrorBanner error={bulkImport.error} title="Import needs attention" onDismiss={bulkImport.reset} />
      <ErrorBanner error={sync.error} title={`${platform.label} sync needs attention`} onDismiss={sync.reset} />

      <Panel title="Add people" description={copy.user_lookup_hint} headingId="add-people-heading" flush>
        <PanelBody>
          <form onSubmit={handleAdd} noValidate>
            <div className={styles.inputGroup}>
              <FormControl>
                <FormControl.Label visuallyHidden>{`${platform.label} user`}</FormControl.Label>
                <TextInput
                  name="platform_user_id"
                  value={handle}
                  onChange={(event) => setHandle(event.target.value)}
                  placeholder={copy.user_placeholder}
                  autoComplete="off"
                  block
                />
                {handleError && <FormControl.Validation variant="error">{handleError}</FormControl.Validation>}
              </FormControl>
              <Button type="submit" variant="primary" loading={add.loading} disabled={!handle.trim()}>
                Add
              </Button>
            </div>
          </form>
        </PanelBody>

        <Disclosure
          open={importOpen}
          onToggle={setImportOpen}
          summary={
            <span className={layout.row}>
              <UploadIcon size={16} />
              <span className={layout.title}>Import a list</span>
              <span className={layout.hint}>One person per line</span>
            </span>
          }
        >
          <PanelBody>
            <form className={layout.stack} onSubmit={handleImport} noValidate>
              <FormControl>
                <FormControl.Label>Participants</FormControl.Label>
                <Textarea
                  name="participants_text"
                  value={importText}
                  onChange={(event) => setImportText(event.target.value)}
                  rows={5}
                  placeholder={copy.import_placeholder}
                  className={layout.mono}
                  block
                />
                {copy.import_hint && <FormControl.Caption>{copy.import_hint}</FormControl.Caption>}
              </FormControl>
              <div>
                <Button type="submit" loading={bulkImport.loading} disabled={!importText.trim()}>
                  Import participants
                </Button>
              </div>
            </form>
          </PanelBody>
        </Disclosure>

        <Disclosure
          open={syncOpen}
          onToggle={setSyncOpen}
          summary={
            <span className={layout.row}>
              <SyncIcon size={16} />
              <span className={layout.title}>Sync from a {platform.label} channel</span>
              <span className={layout.hint}>Adds members and refreshes timezones</span>
            </span>
          }
        >
          <PanelBody>
            <form className={layout.stack} onSubmit={handleSync} noValidate>
              <FormControl className={styles.maxWidth}>
                <FormControl.Label>Channel ID or name</FormControl.Label>
                <TextInput
                  name="channel"
                  value={channel}
                  onChange={(event) => setChannel(event.target.value)}
                  placeholder={copy.channel_id_placeholder}
                  autoComplete="off"
                  block
                />
              </FormControl>
              <FormControl>
                <Checkbox checked={deactivateMissing} onChange={(event) => setDeactivateMissing(event.target.checked)} />
                <FormControl.Label>Mark people who aren't in the channel as inactive</FormControl.Label>
              </FormControl>
              <div>
                <Button type="submit" loading={sync.loading}>
                  Sync channel
                </Button>
              </div>
            </form>
          </PanelBody>
        </Disclosure>
      </Panel>
    </>
  );
}

/** A <details> row inside the panel. */
function Disclosure({ summary, open, onToggle, children }: { summary: ReactNode; open: boolean; onToggle: (open: boolean) => void; children: ReactNode }) {
  return (
    <details className={styles.disclosure} open={open} onToggle={(event) => onToggle(event.currentTarget.open)}>
      <summary>
        <ChevronRightIcon className={styles.chevron} size={16} />
        {summary}
      </summary>
      {children}
    </details>
  );
}

/** A 422 import or sync can still have added or updated some rows, so reload before rethrowing. */
async function reloadOnPartialChange(request: Promise<ImportResult>, onChanged: () => void): Promise<ImportResult> {
  try {
    return await request;
  } catch (error) {
    const summary = error instanceof ApiError ? (error.body as { summary?: ImportSummary | null } | undefined)?.summary : null;
    if (summary && summary.created_count + summary.updated_count + summary.deactivated_count > 0) onChanged();
    throw error;
  }
}
