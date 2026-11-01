import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { useNavigate } from "react-router";
import { Button } from "@primer/react";
import { ApiError, SESSION_PATH, configureSessionHooks, del, post, refreshSession, setCsrfToken } from "../api/client";
import type { Bootstrap, SignInParams } from "../api/types";
import { ErrorBanner } from "../components/ErrorBanner";
import { LoadingState } from "../components/LoadingState";
import { SessionContext, type SessionValue } from "./context";

/** Loads the bootstrap (GET /api/session) and keeps the API client's CSRF token in sync. */
export function SessionProvider({ children }: { children: ReactNode }) {
  const navigate = useNavigate();
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
  const [loadError, setLoadError] = useState<ApiError | null>(null);
  const [attempt, setAttempt] = useState(0);

  const apply = useCallback((next: Bootstrap) => {
    setCsrfToken(next.csrf_token);
    setBootstrap(next);
    setLoadError(null);
    return next;
  }, []);

  useEffect(() => {
    configureSessionHooks({
      onBootstrap: apply,
      // Re-fetching the (now signed-out) bootstrap lets the route guards send
      // the person to /session/new?next=… for the page they were on.
      onUnauthorized: () => {
        refreshSession().catch(() => {});
      },
    });
    return () => configureSessionHooks({});
  }, [apply]);

  useEffect(() => {
    let cancelled = false;
    refreshSession().catch((error: unknown) => {
      if (!cancelled) setLoadError(error instanceof ApiError ? error : new ApiError(0, undefined));
    });
    return () => {
      cancelled = true;
    };
  }, [attempt]);

  const refresh = useCallback(() => refreshSession(), []);

  const signIn = useCallback(
    async (params: SignInParams) => apply(await post<Bootstrap>(SESSION_PATH, params, { skipUnauthorizedHandler: true })),
    [apply],
  );

  const signOut = useCallback(async () => {
    apply(await del<Bootstrap>(SESSION_PATH, undefined, { skipUnauthorizedHandler: true }));
    navigate("/session/new", { replace: true });
  }, [apply, navigate]);

  const consumeFlash = useCallback(() => {
    const pending = bootstrap?.flash ?? [];
    if (pending.length > 0) setBootstrap((current) => current && { ...current, flash: [] });
    return pending;
  }, [bootstrap]);

  const value = useMemo<SessionValue | null>(
    () => (bootstrap ? { bootstrap, refresh, signIn, signOut, consumeFlash } : null),
    [bootstrap, refresh, signIn, signOut, consumeFlash],
  );

  if (!value) {
    if (loadError) {
      return (
        <div style={{ maxWidth: 560, margin: "var(--base-size-64) auto", padding: "0 var(--base-size-16)" }}>
          <ErrorBanner
            title="Couldn't load Standup Bot"
            error={loadError}
            action={<Button onClick={() => setAttempt((n) => n + 1)}>Try again</Button>}
          />
        </div>
      );
    }
    return <LoadingState label="Loading Standup Bot…" fullPage />;
  }

  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}
