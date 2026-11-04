import { useEffect, useId, useState, type ChangeEvent, type ReactElement } from "react";
import { Autocomplete, FormControl } from "@primer/react";
import { HashIcon, LockIcon } from "@primer/octicons-react";
import { get } from "../../../api/client";
import type { ChannelOption, ChannelOptionsPayload } from "../../../api/types/standups";
import type { PlatformKey } from "../../../api/types";
import { toApiError } from "../../../hooks/useApi";
import styles from "./StandupForm.module.css";

const SEARCH_DELAY_MS = 300;

export interface ChannelPickerProps {
  platform: PlatformKey;
  /** The stored channel: an ID once one is picked, or a typed name. */
  channel: string;
  /** The picked channel's name; blank for a typed one. */
  channelName: string;
  onChange: (changes: { platformChannel: string; platformChannelName: string }) => void;
  placeholder: string;
  error?: string;
}

interface SearchResult {
  query: string;
  records: ChannelOption[];
  success: boolean;
  message: string | null;
  action: string | null;
}

type MenuItem = { id: string; text: string; leadingVisual: ReactElement; trailingVisual?: ReactElement; metadata: ChannelOption };

function channelName(option: ChannelOption): string {
  return option.name ?? option.label.replace(/^#/, "");
}

/**
 * "Post summaries to" for Slack: searches channels as you type
 * (GET /api/standups/channel_options) and stores the picked channel's ID and
 * name. A typed name that isn't picked is saved as-is.
 */
export function ChannelPicker({ platform, channel, channelName: name, onChange, placeholder, error }: ChannelPickerProps) {
  const labelId = useId();
  const linked = name !== "" && channel !== "" && channel !== name;
  const [text, setText] = useState(() => (linked ? name : channel));
  const [picked, setPicked] = useState<ChannelOption | null>(null);
  const [result, setResult] = useState<SearchResult | null>(null);
  // Only search once someone types, not for a channel that was saved by name.
  const [typed, setTyped] = useState(false);
  const query = typed && !linked ? text.trim().replace(/^#/, "") : "";

  useEffect(() => {
    if (!query) return;
    const controller = new AbortController();
    const timer = window.setTimeout(() => {
      const params = new URLSearchParams({ platform, query });
      get<ChannelOptionsPayload>(`/api/standups/channel_options?${params.toString()}`, { signal: controller.signal }).then(
        (payload) => setResult({ query, records: payload.records, success: payload.success, message: payload.message, action: payload.action }),
        (failure: unknown) => {
          if (controller.signal.aborted) return;
          setResult({ query, records: [], success: false, message: toApiError(failure).message, action: null });
        },
      );
    }, SEARCH_DELAY_MS);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [query, platform]);

  const current = result && result.query === query ? result : null;
  const searching = query !== "" && !current;
  // Only the current query's results, so a stale channel can't be picked while the next search loads.
  const items: MenuItem[] = (current ? current.records : []).map((option) => {
    const meta = [option.is_private && "private", option.is_member === false && "bot not invited"].filter(Boolean).join(" · ");
    return {
      id: option.id,
      text: channelName(option),
      leadingVisual: option.is_private ? <LockIcon aria-hidden /> : <HashIcon aria-hidden />,
      trailingVisual: meta ? <span className={styles.channelMeta}>{meta}</span> : undefined,
      metadata: option,
    };
  });

  const handleInput = (event: ChangeEvent<HTMLInputElement>) => {
    setText(event.target.value);
    setTyped(true);
    setPicked(null);
    onChange({ platformChannel: event.target.value.trim().replace(/^#/, ""), platformChannelName: "" });
  };

  const handleSelectedChange = (selected: MenuItem | MenuItem[]) => {
    const item = Array.isArray(selected) ? selected[0] : selected;
    if (!item) return;
    setText(item.text);
    setPicked(item.metadata);
    onChange({ platformChannel: item.metadata.id, platformChannelName: item.text });
  };

  const searchNote = current && (current.success ? current.action : [current.message, current.action].filter(Boolean).join(" "));

  return (
    <FormControl required>
      <FormControl.Label id={labelId}>Post summaries to</FormControl.Label>
      <Autocomplete>
        <Autocomplete.Input
          block
          value={text}
          placeholder={placeholder}
          leadingVisual="#"
          validationStatus={error ? "error" : undefined}
          onChange={handleInput}
        />
        {/* Mounted only while searching, so screen readers don't hear an empty menu on load. */}
        {query && (
          <Autocomplete.Overlay>
            <Autocomplete.Menu
              aria-labelledby={labelId}
              items={items}
              selectedItemIds={[]}
              selectionVariant="single"
              loading={searching && items.length === 0}
              filterFn={() => true}
              onSelectedChange={handleSelectedChange}
              emptyStateText={current && !current.success ? current.message : "No channels matched. The typed name will be used."}
            />
          </Autocomplete.Overlay>
        )}
      </Autocomplete>
      <FormControl.Caption>
        {linked ? (
          <>
            Linked to <strong>#{name}</strong> <span className={styles.channelMeta}>({channel})</span>.
            {picked?.is_member === false && " Invite the bot to the channel so it can post there."}
          </>
        ) : (
          "Search your channels and pick one, or type a channel name."
        )}
        {searchNote ? ` ${searchNote}` : ""}
      </FormControl.Caption>
      {error && <FormControl.Validation variant="error">{error}</FormControl.Validation>}
    </FormControl>
  );
}
