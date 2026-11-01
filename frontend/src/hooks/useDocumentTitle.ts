import { useEffect } from "react";

export const APP_NAME = "Standup Bot";

/** Sets `document.title` to "<title> · Standup Bot" (just "Standup Bot" without a title). */
export function useDocumentTitle(title?: string | null): void {
  useEffect(() => {
    document.title = title ? `${title} · ${APP_NAME}` : APP_NAME;
  }, [title]);
}
