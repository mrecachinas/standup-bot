import { useEffect, useId, useState, type ChangeEvent, type KeyboardEvent, type ReactElement } from "react";
import { Autocomplete, FormControl, IconButton } from "@primer/react";
import { PlusIcon, UndoIcon, XIcon } from "@primer/octicons-react";
import { get } from "../../../api/client";
import type { PeopleSearchPayload, PersonResult } from "../../../api/types/standups";
import type { PlatformKey } from "../../../api/types";
import { Avatar } from "../../../components";
import { toApiError } from "../../../hooks/useApi";
import { addChips, chipFromHandle, chipFromPerson, chipLabel, splitHandles, type PersonChip } from "./formState";
import styles from "./StandupForm.module.css";

const SEARCH_DELAY_MS = 300;
const ADD_HANDLE_ID = "__add-handle__";

export interface PeoplePickerProps {
  platform: PlatformKey;
  people: PersonChip[];
  onChange: (people: PersonChip[]) => void;
  /** Text typed but not turned into a chip yet; it's sent as `participant_handles` on save. */
  query: string;
  onQueryChange: (query: string) => void;
  placeholder: string;
  describedBy?: string;
}

interface SearchResult {
  query: string;
  people: PersonResult[];
  message: string | null;
  success: boolean;
}

type MenuItem = { id: string; text: string; leadingVisual?: ReactElement; metadata?: PersonResult };

/**
 * The roster as removable chips, plus an input that searches the chat
 * platform's people (GET /api/people) or takes handles typed straight in.
 */
export function PeoplePicker({ platform, people, onChange, query, onQueryChange, placeholder, describedBy }: PeoplePickerProps) {
  const labelId = useId();
  const trimmed = query.trim();
  const [result, setResult] = useState<SearchResult | null>(null);

  useEffect(() => {
    if (!trimmed) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams({ platform, q: trimmed });
      get<PeopleSearchPayload>(`/api/people?${params.toString()}`, { signal: controller.signal }).then(
        (payload) => setResult({ query: trimmed, people: payload.people, message: payload.message, success: payload.success }),
        (error: unknown) => {
          if (controller.signal.aborted) return;
          setResult({ query: trimmed, people: [], message: toApiError(error).message, success: false });
        },
      );
    }, SEARCH_DELAY_MS);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [trimmed, platform]);

  const searching = trimmed !== "" && result?.query !== trimmed;
  const results = trimmed && result ? result.people : [];
  const selectedIds = people.filter((chip) => !chip.destroy).map((chip) => chip.platform_user_id);
  const items: MenuItem[] = results.map((person) => ({
    id: person.platform_user_id,
    text: person.display_name,
    leadingVisual: <Avatar name={person.display_name} src={person.avatar_url} size={20} />,
    metadata: person,
  }));

  const addHandles = (text: string) => {
    const handles = splitHandles(text);
    if (handles.length > 0) onChange(addChips(people, handles.map(chipFromHandle)));
    onQueryChange("");
  };

  const removeChip = (chip: PersonChip) => {
    onChange(chip.fromServer ? people.map((item) => (item.key === chip.key ? { ...item, destroy: true } : item)) : people.filter((item) => item.key !== chip.key));
  };

  const restoreChip = (chip: PersonChip) => {
    onChange(people.map((item) => (item.key === chip.key ? { ...item, destroy: false } : item)));
  };

  const handleSelectedChange = (selected: MenuItem | MenuItem[]) => {
    const nowSelected = new Set((Array.isArray(selected) ? selected : [selected]).filter(Boolean).map((item) => item.id));
    const wasSelected = new Set(selectedIds);
    let next = people;
    for (const item of items) {
      const person = item.metadata;
      if (!person) continue;
      if (nowSelected.has(item.id) && !wasSelected.has(item.id)) {
        const existing = next.find((chip) => chip.platform_user_id === person.platform_user_id);
        next = existing ? next.map((chip) => (chip === existing ? { ...chip, destroy: false } : chip)) : addChips(next, [chipFromPerson(person)]);
      } else if (!nowSelected.has(item.id) && wasSelected.has(item.id)) {
        const chip = next.find((candidate) => candidate.platform_user_id === person.platform_user_id);
        if (chip) next = chip.fromServer ? next.map((candidate) => (candidate === chip ? { ...candidate, destroy: true } : candidate)) : next.filter((candidate) => candidate !== chip);
      }
    }
    onChange(next);
    onQueryChange("");
  };

  const handleKeyDown = (event: KeyboardEvent<HTMLInputElement>) => {
    const input = event.currentTarget;
    if (event.key === ",") {
      event.preventDefault();
      addHandles(input.value);
    } else if (event.key === "Enter" && !event.nativeEvent.isComposing) {
      // Let the menu pick the highlighted person; otherwise add what was typed.
      if (input.getAttribute("aria-expanded") === "true" && input.getAttribute("aria-activedescendant")) return;
      event.preventDefault();
      addHandles(input.value);
    }
  };

  return (
    <div className={styles.people}>
      {people.length > 0 && (
        <ul className={styles.chips} aria-label="People in this standup">
          {people.map((chip) => {
            const name = chipLabel(chip);
            const meta = chip.destroy ? "removed on save" : chip.pending ? "looked up on save" : !chip.active ? "inactive" : null;
            return (
              <li key={chip.key} className={styles.chip} data-removed={chip.destroy || undefined} data-pending={chip.pending || undefined}>
                <Avatar name={name} src={chip.avatar_url} size={20} />
                <span className={styles.chipName}>{name}</span>
                {meta && <span className={styles.chipMeta}>{meta}</span>}
                {chip.destroy ? (
                  <IconButton icon={UndoIcon} variant="invisible" size="small" aria-label={`Restore ${name}`} onClick={() => restoreChip(chip)} />
                ) : (
                  <IconButton icon={XIcon} variant="invisible" size="small" aria-label={`Remove ${name}`} onClick={() => removeChip(chip)} />
                )}
              </li>
            );
          })}
        </ul>
      )}

      <FormControl>
        <FormControl.Label id={labelId} visuallyHidden>
          Add people
        </FormControl.Label>
        <Autocomplete>
          <Autocomplete.Input
            block
            value={query}
            placeholder={placeholder}
            onChange={(event: ChangeEvent<HTMLInputElement>) => onQueryChange(event.target.value)}
            onKeyDown={handleKeyDown}
            aria-describedby={describedBy}
          />
          {/* Mounted only while there's a query, so screen readers don't hear an empty menu on load. */}
          {trimmed && (
            <Autocomplete.Overlay>
              <Autocomplete.Menu
                aria-labelledby={labelId}
                items={items}
                selectedItemIds={selectedIds}
                selectionVariant="multiple"
                loading={searching && items.length === 0}
                filterFn={() => true}
                onSelectedChange={handleSelectedChange}
                emptyStateText={result?.message ?? "No matches."}
                addNewItem={{
                  id: ADD_HANDLE_ID,
                  text: `Add “${trimmed}”`,
                  leadingVisual: <PlusIcon />,
                  handleAddItem: () => addHandles(trimmed),
                }}
              />
            </Autocomplete.Overlay>
          )}
        </Autocomplete>
        <FormControl.Caption>
          Search, or type someone's handle and press Enter. Separate several people with commas.
          {result && !result.success && result.query === trimmed && result.message ? ` ${result.message}` : ""}
        </FormControl.Caption>
      </FormControl>
    </div>
  );
}
