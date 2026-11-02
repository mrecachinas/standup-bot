import { Banner } from "@primer/react";
import type { ApiError } from "../../../api/client";
import { ErrorBanner, LoadingState } from "../../../components";

/** A member page before its data arrives: loading, forbidden, or a retryable error. */
export function MemberLoadState({ error, onRetry, what }: { error: ApiError | null; onRetry: () => void; what: string }) {
  if (!error) return <LoadingState label={`Loading ${what}`} />;
  if (error.status === 403) return <ErrorBanner error={error} title={`You can't see ${what}`} />;
  return <ErrorBanner error={error} title={`Couldn't load ${what}`} action={<Banner.PrimaryAction onClick={onRetry}>Try again</Banner.PrimaryAction>} />;
}
