import { useEffect, useRef, useState } from "react";
import { post } from "../../../api/client";
import type { SchedulePreview, StandupFormPayload } from "../../../api/types/standups";

const PREVIEW_DELAY_MS = 250;

/** The browser's IANA zone ("America/New_York"), or null. */
function browserTimeZone(): string | null {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || null;
  } catch {
    return null;
  }
}

/** The Rails zone name for the browser's zone, if the list has one. */
export function detectedZoneName(options: StandupFormPayload["time_zone_options"]): string | null {
  const zone = browserTimeZone();
  return (zone && options.find((option) => option.iana === zone)?.name) || null;
}

/**
 * The editor's "Next runs" preview: re-fetched (debounced) from
 * POST /api/standups/preview whenever the schedule or preview timezone changes.
 */
export function useSchedulePreview(payload: StandupFormPayload, schedule: Record<string, unknown>) {
  const [timezone, setTimezone] = useState(() =>
    payload.detect_preview_timezone ? (detectedZoneName(payload.time_zone_options) ?? payload.preview_timezone) : payload.preview_timezone,
  );
  const [state, setState] = useState<{ preview: SchedulePreview; error: string | null; loading: boolean }>({
    preview: payload.schedule_preview,
    error: null,
    loading: false,
  });
  const [nonce, setNonce] = useState(0);
  const body = { standup: { platform: payload.platform.key, ...schedule }, preview_timezone: timezone };
  const key = JSON.stringify(body);
  // What the server's initial preview already shows; nothing to fetch until it changes.
  const fetchedKey = useRef(JSON.stringify({ standup: { platform: payload.platform.key, ...schedule }, preview_timezone: payload.preview_timezone }));
  const fetchedNonce = useRef(0);

  useEffect(() => {
    if (key === fetchedKey.current && nonce === fetchedNonce.current) return;
    const controller = new AbortController();
    const delay = nonce !== fetchedNonce.current ? 0 : PREVIEW_DELAY_MS;
    const timer = window.setTimeout(() => {
      fetchedKey.current = key;
      fetchedNonce.current = nonce;
      setState((current) => ({ ...current, loading: true }));
      post<SchedulePreview>("/api/standups/preview", JSON.parse(key), { signal: controller.signal }).then(
        (preview) => setState({ preview, error: null, loading: false }),
        () => {
          if (!controller.signal.aborted) setState((current) => ({ ...current, error: "Couldn't load the preview. Try again.", loading: false }));
        },
      );
    }, delay);
    return () => {
      window.clearTimeout(timer);
      controller.abort();
    };
  }, [key, nonce]);

  return { ...state, timezone, setTimezone, refresh: () => setNonce((n) => n + 1) };
}

