import { useCallback } from "react";
import type { Standup } from "../../../api/types";
import { useApi } from "../../../hooks/useApi";
import { useDocumentTitle } from "../../../hooks/useDocumentTitle";

/**
 * Loads one of a standup's tabs and titles the page "<tab> · <standup>".
 * `setStandup` merges an updated standup (e.g. after pause/resume) into the payload.
 */
export function useStandupPage<T extends { standup: { name: string } }>(path: string, tab: string | ((data: T) => string) | null) {
  const query = useApi<T>(path);
  const { data, setData } = query;
  const tabTitle = typeof tab === "function" ? (data ? tab(data) : null) : tab;
  useDocumentTitle(data ? [tabTitle, data.standup.name].filter(Boolean).join(" · ") : (tabTitle ?? "Standup"));

  const setStandup = useCallback(
    (standup: Standup) => setData((current) => ({ ...(current as T), standup: { ...(current as T).standup, ...standup } })),
    [setData],
  );

  return { ...query, setStandup };
}
