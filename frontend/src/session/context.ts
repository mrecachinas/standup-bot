import { createContext, useContext } from "react";
import type { Bootstrap, FlashMessage, SignInParams } from "../api/types";

export interface SessionValue {
  /** The latest GET /api/session payload. Always loaded inside the router. */
  bootstrap: Bootstrap;
  /** Re-fetch the bootstrap, e.g. after creating, renaming, pausing or deleting a standup (sidebar). */
  refresh: () => Promise<Bootstrap>;
  /** POST /api/session; throws ApiError (401) on bad credentials. */
  signIn: (params: SignInParams) => Promise<Bootstrap>;
  /** DELETE /api/session and go to the sign-in page. */
  signOut: () => Promise<void>;
  /** Returns the server flash from the bootstrap and clears it (FlashRegion shows them). */
  consumeFlash: () => FlashMessage[];
}

export const SessionContext = createContext<SessionValue | null>(null);

export function useSession(): SessionValue {
  const value = useContext(SessionContext);
  if (!value) throw new Error("useSession must be used inside <SessionProvider>");
  return value;
}

export function useOptionalSession(): SessionValue | null {
  return useContext(SessionContext);
}

/** Call after a standup is created, renamed, paused, resumed or deleted so the sidebar list updates. */
export function useRefreshSidebar(): () => Promise<void> {
  const session = useContext(SessionContext);
  return async () => {
    if (session) await session.refresh();
  };
}
