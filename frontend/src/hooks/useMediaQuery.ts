import { useCallback, useSyncExternalStore } from "react";

/** Primer's `sm` breakpoint: phones in portrait. */
export const NARROW_QUERY = "(max-width: 543.98px)";

/** Whether a CSS media query matches, kept in sync as the viewport changes. */
export function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (onChange: () => void) => {
      const list = window.matchMedia(query);
      list.addEventListener("change", onChange);
      return () => list.removeEventListener("change", onChange);
    },
    [query],
  );
  return useSyncExternalStore(
    subscribe,
    () => window.matchMedia(query).matches,
    () => false,
  );
}
