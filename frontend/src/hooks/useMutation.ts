import { useCallback, useContext, useLayoutEffect, useRef, useState } from "react";
import type { ApiError } from "../api/client";
import { FlashContext } from "../flash/context";
import { SessionContext } from "../session/context";
import { toApiError } from "./useApi";

export interface MutationOptions<TResult> {
  /** Runs after a successful call (e.g. navigate, reload a useApi). */
  onSuccess?: (result: TResult) => void | Promise<void>;
  /**
   * Success toast. Defaults to the response's `notice` when there is one; pass
   * a string or function to override, or `false` for none.
   */
  successMessage?: string | ((result: TResult) => string | undefined) | false;
  /** Show the error as a toast as well as in `error` (default false: show it inline with ErrorBanner). */
  flashError?: boolean;
  /** Refresh the bootstrap afterwards so the sidebar's standup list updates. */
  refreshSidebar?: boolean;
}

export interface Mutation<TArgs extends unknown[], TResult> {
  /** Resolves to the result, or `undefined` if the call failed (see `error`). Never rejects. */
  run: (...args: TArgs) => Promise<TResult | undefined>;
  loading: boolean;
  /** The last failure: `error.fieldErrors` feeds FormControl.Validation. */
  error: ApiError | null;
  reset: () => void;
}

/**
 * Wraps a write, e.g.
 * `useMutation((body) => patch(`/api/standups/${id}`, body), { refreshSidebar: true })`.
 */
export function useMutation<TArgs extends unknown[], TResult>(
  fn: (...args: TArgs) => Promise<TResult>,
  options: MutationOptions<TResult> = {},
): Mutation<TArgs, TResult> {
  const flash = useContext(FlashContext);
  const session = useContext(SessionContext);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<ApiError | null>(null);
  const latest = useRef({ fn, options });
  useLayoutEffect(() => {
    latest.current = { fn, options };
  });

  const run = useCallback(
    async (...args: TArgs) => {
      const { fn: call, options: opts } = latest.current;
      setLoading(true);
      setError(null);
      try {
        const result = await call(...args);
        const message = successMessageFor(result, opts.successMessage);
        if (message) flash.push({ type: "success", message });
        if (opts.refreshSidebar && session) await session.refresh().catch(() => undefined);
        await opts.onSuccess?.(result);
        return result;
      } catch (caught) {
        const apiError = toApiError(caught);
        setError(apiError);
        if (opts.flashError) flash.push({ type: "danger", message: apiError.message });
        return undefined;
      } finally {
        setLoading(false);
      }
    },
    [flash, session],
  );

  const reset = useCallback(() => setError(null), []);

  return { run, loading, error, reset };
}

function successMessageFor<TResult>(result: TResult, option: MutationOptions<TResult>["successMessage"]): string | undefined {
  if (option === false) return undefined;
  if (typeof option === "string") return option;
  if (typeof option === "function") return option(result);
  if (typeof result === "object" && result !== null && "notice" in result) {
    const notice = (result as { notice?: unknown }).notice;
    return typeof notice === "string" ? notice : undefined;
  }
  return undefined;
}
