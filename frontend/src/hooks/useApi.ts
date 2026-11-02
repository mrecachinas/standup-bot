import { useCallback, useEffect, useState } from "react";
import { ApiError, get } from "../api/client";

export interface ApiState<T> {
  /** The last successful response (kept while reloading). */
  data: T | undefined;
  error: ApiError | null;
  /** True until the current request settles (including reloads). */
  loading: boolean;
  /** Fetch again, e.g. after a mutation. */
  reload: () => void;
  /** Replace `data` locally (optimistic updates, or a mutation's response). */
  setData: (update: T | ((current: T | undefined) => T)) => void;
}

interface Result<T> {
  key: string | null;
  data: T | undefined;
  error: ApiError | null;
}

/** GETs `path` (e.g. `/api/standups/${id}`) and re-fetches when it changes. Pass `null` to skip. */
export function useApi<T>(path: string | null): ApiState<T> {
  const [nonce, setNonce] = useState(0);
  const key = path === null ? null : `${nonce}:${path}`;
  const [result, setResult] = useState<Result<T>>({ key: null, data: undefined, error: null });

  useEffect(() => {
    if (path === null || key === null) return;
    const controller = new AbortController();

    get<T>(path, { signal: controller.signal }).then(
      (data) => setResult({ key, data, error: null }),
      (error: unknown) => {
        if (controller.signal.aborted) return;
        setResult((current) => ({ key, data: current.data, error: toApiError(error) }));
      },
    );

    return () => controller.abort();
  }, [path, key]);

  const reload = useCallback(() => setNonce((n) => n + 1), []);

  const setData = useCallback((update: T | ((current: T | undefined) => T)) => {
    setResult((current) => ({
      ...current,
      data: typeof update === "function" ? (update as (current: T | undefined) => T)(current.data) : update,
    }));
  }, []);

  return {
    data: result.data,
    error: result.key === key ? result.error : null,
    loading: key !== null && result.key !== key,
    reload,
    setData,
  };
}

export function toApiError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  return new ApiError(0, undefined, "Couldn't reach the server. Check your connection and try again.");
}
