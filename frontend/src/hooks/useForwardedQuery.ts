import { useSearchParams } from "react-router";

/**
 * `base` plus the page URL's `keys` (in that order, skipping blanks) and any
 * `fixed` params, e.g. `/api/standups/7/analytics?view=insights&start_date=…`.
 */
export function useForwardedQuery(base: string, keys: readonly string[], fixed: Record<string, string> = {}): string {
  const [searchParams] = useSearchParams();
  const query = new URLSearchParams(fixed);
  for (const key of keys) {
    const value = searchParams.get(key);
    if (value) query.set(key, value);
  }
  const queryString = query.toString();
  return queryString ? `${base}?${queryString}` : base;
}
